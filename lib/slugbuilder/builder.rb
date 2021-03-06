require 'securerandom'
require 'shellwords'
require 'yaml'
require 'fileutils'
require 'open3'

module Slugbuilder
  class Builder
    def initialize(repo:, git_ref:, stdout: $stdout)
      @stdout = stdout
      @base_dir = Shellwords.escape(Slugbuilder.config.base_dir)
      @output_dir = Shellwords.escape(Slugbuilder.config.output_dir)
      @buildpacks_dir = File.join(@base_dir, 'buildpacks')
      repo_matches = parse_git_url(repo)
      @repo = "#{repo_matches[:org]}/#{repo_matches[:name]}"
      @cache_dir = File.join(Shellwords.escape(Slugbuilder.config.cache_dir), @repo)
      @env_dir = File.join(@base_dir, 'environment', SecureRandom.hex)
      @git_url = normalize_git_url(repo)
      @git_ref = git_ref
      @git_dir = File.join(@base_dir, 'git', @repo)
      @build_dir = File.join(@base_dir, @repo, git_ref, SecureRandom.hex)

      setup

      if block_given?
        yield(repo: @repo, git_ref: git_ref, git_url: @git_url)
      end
    end

    def build(clear_cache: false, env: {}, prebuild: nil, postbuild: nil, slug_name: nil, buildpacks: Slugbuilder.config.buildpacks)
      FileUtils.mkdir_p(@env_dir)

      @buildpacks = buildpacks
      @env = env.map { |k, v| [k.to_s, v.to_s] }.to_h
      @slug_file = slug_name ? "#{slug_name}.tgz" : Shellwords.escape("#{@repo.gsub('/', '.')}.#{@git_ref}.#{@git_sha}.#{SecureRandom.hex}.tgz")
      wipe_cache if clear_cache

      prebuild.call(repo: @repo, git_ref: @git_ref, git_url: @git_url) if prebuild

     Bundler.with_clean_env do
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

      postbuild.call(repo: @repo, git_ref: @git_ref, git_sha: @git_sha, git_url: @git_url, request_id: @request_id, stats: stats, slug: File.join(@output_dir, @slug_file)) if postbuild
      if block_given?
        yield(repo: @repo, git_ref: @git_ref, git_sha: @git_sha, git_url: @git_url, request_id: @request_id, stats: stats, slug: File.join(@output_dir, @slug_file))
      end

      # clear environment and build
      FileUtils.rm_rf(@env_dir)
      FileUtils.rm_rf(@build_dir)
      return true
    rescue => e
      stitle("Failed: #{e}\n")
      return false
    end


    private

    def wipe_cache
      FileUtils.rm_rf(@cache_dir)
      FileUtils.rm_rf(@buildpacks_dir)
      FileUtils.mkdir_p(@cache_dir)
      FileUtils.mkdir_p(@buildpacks_dir)
    end

    def build_and_release
      @build_time = realtime do
        set_environment
        buildpacks = fetch_buildpacks
        run_hook('pre-compile')
        run_buildpacks(buildpacks)
        run_hook('post-compile')
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
      ENV['STACK'] = Slugbuilder.config.heroku_stack
      @request_id = SecureRandom.urlsafe_base64(32)
      ENV['REQUEST_ID'] = @request_id
      ENV['SOURCE_VERSION'] = @git_sha

      # write user envs to files
      write_user_envs(@env)

      ENV['HOME'] = @build_dir
      ENV['APP_DIR'] = @build_dir

      stitle('Build environment')
      ENV.to_h.merge(@env).each do |k, v|
        stext("#{k}=#{v}")
      end
    end

    def create_dirs
      FileUtils.mkdir_p(@cache_dir)
      FileUtils.mkdir_p(@base_dir)
      FileUtils.mkdir_p(@buildpacks_dir)
      FileUtils.mkdir_p(@output_dir)
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
      rc = run("git clone --quiet #{@git_url} #{@git_dir}")
      fail "Failed to download repo: #{@repo}" if rc != 0
    end

    def copy_app
      # copy dotfiles but not .git, ., or ..
      files = Dir.glob("#{@git_dir}/**", File::FNM_DOTMATCH).reject { |file| file =~ /\.git|\.$|\.\.$/ }
      FileUtils.cp_r(files, @build_dir)
    end

    def get_buildpack_name(url)
      matches = parse_git_url(url)
      "#{matches[:org]}__#{matches[:name]}#{matches[:hash]}"
    end

    def fetch_buildpacks
      @buildpacks << Shellwords.escape(@env['BUILDPACK_URL']) if @env.key?('BUILDPACK_URL')
      fail 'Could not detect buildpack' if @buildpacks.size.zero?

      existing_buildpacks = Dir.entries(@buildpacks_dir)
      @buildpacks.each do |buildpack_url|
        buildpack_matches = parse_git_url(buildpack_url)
        buildpack_name = get_buildpack_name(buildpack_url)
        if !existing_buildpacks.include?(buildpack_name)
          # download buildpack
          stitle("Fetching buildpack: #{buildpack_name}")
          rc = run("git clone --quiet #{normalize_git_url(buildpack_url)} #{@buildpacks_dir}/#{buildpack_name}")
          fail "Failed to download buildpack: #{buildpack_name}" if rc != 0
        else
          # fetch latest
          stitle("Using cached buildpack. Ensuring latest version of buildpack: #{buildpack_name}")
          Dir.chdir("#{@buildpacks_dir}/#{buildpack_name}") do
            rc = run('git reset origin --hard && git pull --quiet')
            fail "Failed to update: #{buildpack_name}" if rc != 0
          end
        end

        # checkout hash
        if buildpack_matches[:hash]
          Dir.chdir("#{@buildpacks_dir}/#{buildpack_name}") do
            rc = run("git fetch --quiet --all && git checkout --quiet #{buildpack_matches[:hash]} && git reset origin --hard && git pull --quiet")
            fail "Failed to fetch and checkout: #{buildpack_matches[:hash]}" if rc != 0
          end
        end
      end

      @buildpacks
    end

    def run_hook(hook_name)
      Dir.chdir(@build_dir) do
        script = "#{@build_dir}/bin/#{hook_name}"
        if File.exists?(script)
          rc, errs = run_echo(script)
          fail "#{errs.join('\n')}\nFailed to run #{script}" if rc != 0
        end
      end
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
      rc, errs = run_echo("#{buildpack}/bin/compile '#{@build_dir}' '#{@cache_dir}' '#{@env_dir}'")
      fail "#{errs.join('\n')}\nCouldn't compile application using buildpack #{buildpack}" if rc != 0
    end

    def release(buildpack)
      # should create .release
      release_file = File.open("#{@build_dir}/.release", 'w')
      rc = run("#{buildpack}/bin/release '#{@build_dir}'") do |line|
        release_file.print(line)
      end
      release_file.close

      fail "Couldn't release application using buildpack #{buildpack}" if rc != 0
    end

    def build_slug
      rc = 1
      errs = []
      # use pigz if available
      compression = `which pigz` != '' ? '--use-compress-program=pigz' : ''
      if File.exists?("#{@build_dir}/.slugignore")
        rc, errs = run_echo("tar --exclude='.git' #{compression} -X #{@build_dir}/.slugignore -C #{@build_dir} -cf #{File.join(@output_dir, @slug_file)} .")
      else
        rc, errs = run_echo("tar --exclude='.git' #{compression} -C #{@build_dir} -cf #{File.join(@output_dir, @slug_file)} .")
      end
      fail "#{errs.join('\n')}\nCouldn't create slugfile" if rc != 0
    end

    def slug_size
      @slug_size = File.size(File.join(@output_dir, @slug_file)) / 1024 / 1024
      stitle("Slug size is #{@slug_size} Megabytes.")
    end

    def parse_git_url(url)
      regex = %r{
        ^
        .*?
        (?:(?<host>[^\/@]+)(\/|:))?
        (?<org>[^\/:]+)
        \/
        (?<name>[^\/#\.]+)
        (?:\.git(?:\#(?<hash>.+))?)?
        $
      }x
      url.match(regex)
    end

    def normalize_git_url(url)
      matches = parse_git_url(url)
      fail "Invalid buildpack url: #{url}." unless matches
      if Slugbuilder.config.protocol == 'ssh'
        "git@#{matches[:host] || Slugbuilder.config.git_service}:#{matches[:org]}/#{matches[:name]}.git"
      else
        "https://#{matches[:host] || Slugbuilder.config.git_service}/#{matches[:org]}/#{matches[:name]}.git"
      end
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
      Open3.popen3(cmd) do |stdin, stdout, stderr, thread|
        until stdout.eof? && stderr.eof?
          out = stdout.gets
          err = stderr.gets
          yield(out, err) if block_given?
        end
        thread.value.exitstatus
      end
    end

    def run_echo(cmd)
      errors = []
      status = run(cmd) do |stdout, stderr|
        build_output << stdout if stdout
        errors << stderr if stderr
        @stdout.print(stdout)
      end
      [status, errors]
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
