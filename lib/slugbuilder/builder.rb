require 'faraday'
require 'securerandom'
require 'shellwords'
require 'yaml'
require 'fileutils'

module Slugbuilder
  class Builder
    def initialize(repo:, git_ref:, clear_cache: false, env: {})
      @base_dir = Slugbuilder.config.base_dir
      @upload_url = Slugbuilder.config.upload_url
      @git_dir = Shellwords.escape("#{@base_dir}/git/#{repo}")
      @build_dir = Shellwords.escape("#{@base_dir}/#{repo}/#{git_ref}")
      @cache_dir = Shellwords.escape(Slugbuilder.config.cache_dir)
      @buildpacks_dir = "#{@cache_dir}/buildpacks"
      @slug_file = Shellwords.escape("#{repo.gsub('/', '.')}.#{git_ref}.tgz")
      @env = env
      @repo = repo
      @git_ref = git_ref

      wipe_cache if clear_cache
      setup
    end

    def build
      build_and_release
      stitle("Setup completed in #{@setup_time} seconds")
      stitle("Build completed in #{@build_time} seconds")
      stext("Application compiled in #{@compile_time} seconds")
      stext("Slug compressed in #{@slug_time} seconds")
      stext("Uploaded slug in #{@upload_time} seconds") if @upload_url
      return true
    rescue => e
      stitle("Failed to create slug: #{e}")
      return false
    end


    private

    def wipe_cache
      FileUtils.rm_rf(@cache_dir)
    end

    def build_and_release
      @build_time = realtime do
        set_environment
        buildpacks = fetch_buildpacks
        run_buildpacks(buildpacks)
        @slug_time = realtime { build_slug }
        slug_size
        print_workers
        @upload_time = realtime { upload_slug } if @upload_url
      end
    end

    def setup
      @setup_time = realtime do
        create_dirs
        download_repo unless Dir.exist?(@git_dir)
        checkout_git_ref

        stext("Saving application to #{@build_dir}")
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

      ENV['HOME'] = @build_dir
      ENV['APP_DIR'] = @build_dir

      stitle('Build environment')
      ENV.each do |k, v|
        stext("#{k}=#{v}")
      end
    end

    def create_dirs
      FileUtils.mkdir_p(@base_dir)
      FileUtils.mkdir_p(File.join(@cache_dir, 'buildpacks'))
      # clear old build
      FileUtils.rm_rf(@build_dir)
      FileUtils.mkdir_p(File.join(@build_dir, '.profile.d'))
    end

    def checkout_git_ref
      Dir.chdir(@git_dir) do
        # checkout branch or sha
        # get branch from origin so it is always the most recent
        rc = run("git fetch --all && (git checkout origin/#{@git_ref} || git checkout #{@git_ref})")
        fail "Failed to fetch and checkout: #{@git_ref}" if rc != 0
      end
    end

    def download_repo
      stitle("Fetching #{@repo}")
      rc = run_echo("git clone git@github.com:#{@repo}.git #{@git_dir}")
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
      buildpacks = Slugbuilder.config.buildpacks
      buildpacks << Shellwords.escape(@env['BUILDPACK_URL']) if @env.key?('BUILDPACK_URL')
      fail 'Could not detect buildpack' if buildpacks.size.zero?

      existing_buildpacks = Dir.entries(@buildpacks_dir)
      buildpacks.each do |buildpack_url|
        buildpack_name = get_buildpack_name(buildpack_url)
        if !existing_buildpacks.include?(buildpack_name)
          # download buildpack
          stitle("Fetching buildpack: #{buildpack_name}")
          rc = run("git clone --depth=1 #{buildpack_url} #{@buildpacks_dir}/#{buildpack_name}")
          fail "Failed to download buildpack: #{buildpack_name}" if rc != 0
        else
          # fetch latest
          stitle("Updating buildpack: #{buildpack_name}")
          Dir.chdir("#{@buildpacks_dir}/#{buildpack_name}") do
            rc = run('git pull')
            fail "Failed to update: #{buildpack_name}" if rc != 0
          end
        end
      end

      buildpacks
    end

    def run_buildpacks(buildpacks)
      @compile_time = 0

      buildpacks.each do |buildpack_url|
        buildpack_name = get_buildpack_name(buildpack_url)
        buildpack = "#{@buildpacks_dir}/#{buildpack_name}"
        if run("#{buildpack}/bin/detect #{@build_dir}") == 0
          @compile_time += realtime { compile(buildpack) }
          release(buildpack)
        end
      end

    end

    def compile(buildpack)
      rc = run_echo("#{buildpack}/bin/compile '#{@build_dir}' '#{@cache_dir}'")
      fail "Couldn't compile application using buildpack #{buildpack}" if rc != 0
    end

    def release(buildpack)
      # should create .release
      release_file = File.open("#{@build_dir}/.release", 'w')
      rc = run("#{buildpack}/bin/release '#{@build_dir}' '#{@cache_dir}'") do |line|
        release_file.print(line)
      end
      release_file.close

      fail "Couldn't compile application using buildpack #{buildpack}" if rc != 0
    end

    def build_slug
      rc = 1
      # use pigz if available
      compression = run('which pigz') == 0 ? '--use-compress-program=pigz' : ''
      if File.exists?("#{@build_dir}/.slugignore")
        rc = run_echo("tar --exclude='.git' #{compression} -X #{@build_dir}/.slugignore -C #{@build_dir} -cf #{@slug_file} .")
      else
        rc = run_echo("tar --exclude='.git' #{compression} -C #{@build_dir} -cf #{@slug_file} .")
      end
      fail "Couldn't create slugfile" if rc != 0
    end

    def upload_slug
      stitle("Uploading slug to #{@upload_url}")

      conn = Faraday.new do |f|
        f.request :multipart
        f.adapter :em_http
      end

      response = conn.put(@upload_url, Faraday::UploadIO.new(@slug_file, 'application/x-gzip'))
      fail unless response.status.between?(200, 300)
    end

    def slug_size
      @slug_size = File.size(@slug_file) / 1024 / 1024
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

    def stitle(line)
      STDOUT.puts("-----> #{line}")
    end

    def stext(line)
      STDOUT.puts("       #{line}")
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
        STDOUT.print(line)
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

          ENV[parts[0]] = parts[1]
          @env[parts[0]] = parts[1]
        end
      end
    end
  end
end
