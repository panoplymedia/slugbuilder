require 'securerandom'
require 'shellwords'
require 'yaml'
require 'fileutils'

module Slugbuilder
  class Builder
    def initialize(repo:, git_ref:, clear_cache: false, env: {})
      @base_dir = Slugbuilder.config.base_dir
      @app_dir = Shellwords.escape("#{@base_dir}/git/#{repo}")
      @build_dir = Shellwords.escape("#{@base_dir}/#{repo}/#{git_ref}")
      @cache_dir = Slugbuilder.config.cache_dir
      @buildpack_dir = Slugbuilder.config.buildpack_dir
      @slug_file = Shellwords.escape("#{repo.gsub('/', '.')}.#{git_ref}.tgz")
      @extra_env = env
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
      return true

    rescue => e
      stitle("Failed to create slug: #{e}")
      return false
    end


    private

    def wipe_cache
      FileUtils.rm_rf(@app_dir)
      FileUtils.rm_rf(@build_dir)
      FileUtils.rm_rf(@cache_dir)
    end

    def build_and_release
      @build_time = realtime do
        set_environment
        set_buildpack
        @compile_time = realtime { compile }
        release
        profile_extras
        @slug_time = realtime { build_slug }
        slug_size
        print_workers
      end
    end

    def setup
      @setup_time = realtime do
        unless Dir.exist?(@app_dir)
          create_dirs
          download_repo
        end
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

      ENV['HOME'] = @build_dir
      ENV['APP_DIR'] = @build_dir
      ENV['STACK'] = 'cedar-14'
      # ENV['REQUEST_ID'] = @request_id

      stitle('Build environment')
      ENV.each do |k,v|
        stext("#{k}=#{v}")
      end
    end

    def create_dirs
      FileUtils.mkdir_p(@base_dir)
      FileUtils.mkdir_p(@cache_dir)
      FileUtils.mkdir_p(File.join(@build_dir, '.profile.d'))
    end

    def checkout_git_ref
      Dir.chdir(@app_dir) do
        # checkout branch or sha
        rc = run("git fetch --all && (git checkout origin/#{@git_ref} || git checkout #{@git_ref})")
        fail "Failed to fetch and checkout: #{@git_ref}" if rc != 0
      end
    end

    def download_repo
      stitle("Fetching #{@repo}")
      rc = run_echo("git clone git@github.com:#{@repo}.git #{@app_dir}")
      fail "Failed to download repo: #{@repo}" if rc != 0
    end

    def copy_app
      # copy dotfiles but not .git, ., or ..
      files = Dir.glob("#{@app_dir}/**", File::FNM_DOTMATCH).reject { |file| file =~ /\.git|\.$|\.\.$/ }
      FileUtils.cp_r(files, @build_dir)
    end

    def set_buildpack
      buildpack = nil

      if @extra_env.key?('BUILDPACK_URL')
        stitle('Fetching custom buildpack')
        rc = run("git clone --depth=1 #{Shellwords.escape(@extra_env['BUILDPACK_URL'])} #{@buildpack_dir}/00-custom")
        fail "Failed to download custom buildpack: #{@extra_env['BUILDPACK_URL']}" if rc != 0
      end

      Dir["#{@buildpack_dir}/**"].each do |file|
        if run("#{file}/bin/detect #{@build_dir}") == 0
          buildpack = file
          break
        end
      end
      fail "Could not detect buildpack" unless buildpack

      @buildpack = buildpack
    end

    def compile
      rc = run_echo("#{@buildpack}/bin/compile '#{@build_dir}' '#{@cache_dir}'")
      fail "Couldn't compile application using buildpack #{@buildpack}" if rc != 0
    end

    def release
      # should create .release
      release_file = File.open("#{@build_dir}/.release", "w")
      rc = run("#{@buildpack}/bin/release '#{@build_dir}' '#{@cache_dir}'") do |line|
        release_file.print(line)
      end
      release_file.close

      fail "Couldn't compile application using buildpack #{@buildpack}" if rc != 0
    end

    def profile_extras
      File.open("#{@build_dir}/.profile.d/98extra.sh", 'w') do |file|
        @extra_env.each do |k,v|
          file.puts("export #{Shellwords.escape(k)}=#{Shellwords.escape(v)}")
        end
      end
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
          @extra_env[parts[0]] = parts[1]
        end
      end
    end
  end
end
