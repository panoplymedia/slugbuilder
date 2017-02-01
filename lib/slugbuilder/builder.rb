require 'securerandom'
require 'shellwords'
require 'yaml'
require 'fileutils'

module Slugbuilder
  class Builder
    def initialize(repo:, git_ref:, stdout: $stdout)
      @stdout = stdout
      @base_dir = Slugbuilder.config.base_dir
      @cache_dir = Shellwords.escape(Slugbuilder.config.cache_dir)
      @output_dir = Slugbuilder.config.output_dir
      @buildpacks_dir = File.join(@cache_dir, 'buildpacks')
      @env_dir = File.join(@base_dir, 'environment')
      @repo = repo
      @git_ref = git_ref
      @git_dir = Shellwords.escape(File.join(@base_dir, 'git', repo))
      @build_dir = Shellwords.escape(File.join(@base_dir, repo, git_ref))

      setup

      if block_given?
        yield(repo: repo, git_ref: git_ref)
      end
    end

    def build(clear_cache: false, env: {}, prebuild: nil, postbuild: nil, slug_name: nil, buildpacks: Slugbuilder.config.buildpacks)
      @old_env = ENV.to_h
      # clear environment from previous builds
      FileUtils.rm_rf(@env_dir)
      FileUtils.mkdir_p(@env_dir)

      @buildpacks = buildpacks
      @env = env
      @slug_file = slug_name ? "#{slug_name}.tgz" : Shellwords.escape("#{@repo.gsub('/', '.')}.#{@git_ref}.#{@git_sha}.tgz")
      wipe_cache if clear_cache

      prebuild.call(repo: @repo, git_ref: @git_ref) if prebuild

      with_clean_env do
        build_and_release
      end
      stitle("Setup completed in #{@setup_time} seconds")
      stitle("Build completed in #{@build_time} seconds")
      stext("Application compiled in #{@compile_time} seconds")
      stext("Slug compressed in #{@slug_time} seconds")
      stitle("Slug built to #{File.join(@output_dir, @slug_file)}")
      stats = {
        setup: @setup_time,
        build: @build_time,
        compile: @compile_time,
        slug: @slug_time,
        output: build_output.join('')
      }

      postbuild.call(repo: @repo, git_ref: @git_ref, git_sha: @git_sha, request_id: @request_id, stats: stats, slug: File.join(@output_dir, @slug_file)) if postbuild
      if block_given?
        yield(repo: @repo, git_ref: @git_ref, git_sha: @git_sha, request_id: @request_id, stats: stats, slug: File.join(@output_dir, @slug_file))
      end
      return true
    rescue => e
      stitle("Failed: #{e}\n#{e.backtrace.join("\n")}")
      return false
    ensure
      restore_env
    end


    private

    def restore_env
      ENV.delete_if { true }
      ENV.update(@old_env)
    end

    def with_clean_env
      ENV.delete_if { true }
      yield
      restore_env
    end

    def wipe_cache
      FileUtils.rm_rf(@cache_dir)
      FileUtils.mkdir_p(@buildpacks_dir)
    end

    def build_and_release
      @build_time = realtime do
        set_environment
        buildpacks = fetch_buildpacks
        run_buildpacks(buildpacks)
        @slug_time = realtime { build_slug }
        slug_size
        print_workers
      end
    end

    def setup
      @setup_time = realtime do
        create_dirs
        download_repo unless Dir.exist?(@git_dir)
        checkout_git_ref

        stitle("Saving application to #{@build_dir}")
        copy_app
      end
    end

    def slug_size
      @slug_size = File.size(@slug_file) / 1024 / 1024
      stitle("Slug size is #{@slug_size} Megabytes.")
    end

    def set_environment
      load_env_file("#{@cache_dir}/env")
      load_env_file("#{@build_dir}/.env")
      ENV['STACK'] = 'cedar-14'
      @request_id = SecureRandom.urlsafe_base64(32)
      ENV['REQUEST_ID'] = @request_id
      ENV['SOURCE_VERSION'] = @git_sha

      # write user envs to files
      write_user_envs(@env)

      ENV['HOME'] = @build_dir
      ENV['APP_DIR'] = @build_dir

      stitle('Build environment')
      ENV.each do |k, v|
        stext("#{k}=#{v}")
      end
    end

    def create_dirs
      FileUtils.mkdir_p(@base_dir)
      FileUtils.mkdir_p(@buildpacks_dir)
      FileUtils.mkdir_p(@output_dir)
      # clear old build
      FileUtils.rm_rf(@build_dir)
      FileUtils.mkdir_p(File.join(@build_dir, '.profile.d'))
    end

    def checkout_git_ref
      Dir.chdir(@git_dir) do
        # checkout branch or sha
        # get branch from origin so it is always the most recent
        rc = run("git fetch --quiet --all && (git checkout --quiet origin/#{@git_ref} || git checkout --quiet #{@git_ref})")
        fail "Failed to fetch and checkout: #{@git_ref}" if rc != 0
        @git_sha = `git rev-parse HEAD`.strip
      end
    end

    def download_repo
      stitle("Fetching #{@repo}")
      rc = run("git clone --quiet git@#{Slugbuilder.config.git_service}:#{@repo}.git #{@git_dir}")
      fail "Failed to download repo: #{@repo}" if rc != 0
    end

    def copy_app
      # copy dotfiles but not .git, ., or ..
      files = Dir.glob("#{@git_dir}/**", File::FNM_DOTMATCH).reject { |file| file =~ /\.git|\.$|\.\.$/ }
      FileUtils.cp_r(files, @build_dir)
    end

    def get_buildpack_name(url)
      url.match(/.+\/(.+?)\.git$/)[1]
    end

    def fetch_buildpacks
      @buildpacks << Shellwords.escape(@env['BUILDPACK_URL']) if @env.key?('BUILDPACK_URL')
      fail 'Could not detect buildpack' if @buildpacks.size.zero?

      existing_buildpacks = Dir.entries(@buildpacks_dir)
      @buildpacks.each do |buildpack_url|
        buildpack_name = get_buildpack_name(buildpack_url)
        if !existing_buildpacks.include?(buildpack_name)
          # download buildpack
          stitle("Fetching buildpack: #{buildpack_name}")
          rc = run("git clone --quiet --depth=1 #{buildpack_url} #{@buildpacks_dir}/#{buildpack_name}")
          fail "Failed to download buildpack: #{buildpack_name}" if rc != 0
        else
          # fetch latest
          stitle("Using cached buildpack. Ensuring latest version of buildpack: #{buildpack_name}")
          Dir.chdir("#{@buildpacks_dir}/#{buildpack_name}") do
            rc = run('git pull --quiet')
            fail "Failed to update: #{buildpack_name}" if rc != 0
          end
        end
      end

      @buildpacks
    end

    def run_buildpacks(buildpacks)
      @compile_time = 0

      buildpacks.each do |buildpack_url|
        buildpack_name = get_buildpack_name(buildpack_url)
        buildpack = File.join(@buildpacks_dir, buildpack_name)
        if run("#{buildpack}/bin/detect #{@build_dir}") == 0
          @compile_time += realtime { compile(buildpack) }

          # load environment for subsequent buildpacks
          load_export_env(File.join(buildpack, 'export'))

          release(buildpack)
        end
      end

    end

    def compile(buildpack)
      rc = run_echo("#{buildpack}/bin/compile '#{@build_dir}' '#{@cache_dir}' '#{@env_dir}'")
      fail "Couldn't compile application using buildpack #{buildpack}" if rc != 0
    end

    def release(buildpack)
      # should create .release
      release_file = File.open("#{@build_dir}/.release", 'w')
      rc = run("#{buildpack}/bin/release '#{@build_dir}'") do |line|
        release_file.print(line)
      end
      release_file.close

      fail "Couldn't compile application using buildpack #{buildpack}" if rc != 0
    end

    def build_slug
      rc = 1
      # use pigz if available
      compression = `which pigz` != '' ? '--use-compress-program=pigz' : ''
      if File.exists?("#{@build_dir}/.slugignore")
        rc = run_echo("tar --exclude='.git' #{compression} -X #{@build_dir}/.slugignore -C #{@build_dir} -cf #{File.join(@output_dir, @slug_file)} .")
      else
        rc = run_echo("tar --exclude='.git' #{compression} -C #{@build_dir} -cf #{File.join(@output_dir, @slug_file)} .")
      end
      fail "Couldn't create slugfile" if rc != 0
    end

    def slug_size
      @slug_size = File.size(File.join(@output_dir, @slug_file)) / 1024 / 1024
      stitle("Slug size is #{@slug_size} Megabytes.")
    end

    def print_workers
      workers = {}
      if File.exists?("#{@build_dir}/Procfile")
        procfile = YAML.load_file("#{@build_dir}/Procfile")
        workers.merge!(procfile)
      end

      if File.exists?("#{@build_dir}/.release")
        procfile = YAML.load_file("#{@build_dir}/.release")
        workers.merge!(procfile['default_process_types']) if procfile.key?('default_process_types')
      end

      stitle("Process Types: #{workers.keys.join(', ')}")
    end

    def build_output
      @build_output ||= []
    end

    def stitle(line)
      build_output << "-----> #{line}\n"
      @stdout.puts("-----> #{line}")
    end

    def stext(line)
      build_output << "       #{line}\n"
      @stdout.puts("       #{line}")
    end

    def realtime
      t0 = Time.now
      yield
      ((Time.now - t0).to_i * 100) / 100.0
    end

    def run(cmd)
      IO.popen(cmd) do |io|
        until io.eof?
          data = io.gets
          yield data if block_given?
        end
      end
      $?.exitstatus
    end

    def run_echo(cmd)
      run(cmd) do |line|
        build_output << line
        @stdout.print(line)
      end
    end

    def load_export_env(file)
      if File.exists?(file)
        exports = IO.read(file).split('export')
        exports.each do |line|
          parts = line.split(/=/, 2)
          next if parts.length != 2
          name, val = parts
          name.strip!
          val = val.strip.split(/\n/).join.gsub('"', '')

          ENV[name] = `echo "#{val}"`.strip
        end
      end
    end

    def write_user_envs(envs)
      envs.each do |key, val|
        File.open(File.join(@env_dir, key.to_s), 'w') do |file|
          file.write(val.to_s)
        end
      end
    end

    def load_env_file(file)
      if File.exists?(file)
        new_envs = IO.readlines(file)
        new_envs.each do |line|
          line.strip!
          next if line.match(/^#/)

          parts = line.split(/=/, 2)
          next if parts.length != 2

          @env[parts[0]] = parts[1]
        end
      end
    end
  end
end
