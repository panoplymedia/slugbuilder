require 'spec_helper'

describe Slugbuilder::Builder do
  repo = 'jdlehman/node-js-sample'

  before(:each) do
    Slugbuilder.configure do |config|
      config.base_dir = '/tmp/slugbuilder'
      config.cache_dir = '/tmp/slugbuilder-cache'
      config.output_dir = '/tmp/slugs'
      config.protocol = 'https'
      config.buildpacks = ['https://github.com/heroku/heroku-buildpack-nodejs.git']
    end
  end
  after(:each) do
    Slugbuilder.reset
  end
  after(:all) do
    FileUtils.rm_rf('/tmp/slugbuilder')
    FileUtils.rm_rf('/tmp/slugbuilder-cache')
    FileUtils.rm_rf('/tmp/slugs')
  end

  describe '#initialize' do
    before do
      Slugbuilder::Builder.new(repo: repo, git_ref: 'master', stdout: StringIO.new)
    end

    it 'creates directories' do
      expect(Dir['/tmp/*']).to include('/tmp/slugbuilder', '/tmp/slugbuilder-cache', '/tmp/slugs')
    end

    it 'pulls down git repo and copies to build directory' do
      expect(Dir['/tmp/slugbuilder/**/**']).to include(
        '/tmp/slugbuilder/git/jdlehman/node-js-sample/app.json',
        '/tmp/slugbuilder/jdlehman/node-js-sample/master/app.json'
      )
    end

    it 'accepts a prebuild block' do
      Slugbuilder::Builder.new(repo: repo, git_ref: 'master', stdout: StringIO.new) do |args|
        expect(args).to eq({repo: repo, git_ref: 'master', git_url: 'https://github.com/jdlehman/node-js-sample.git'})
      end
    end

    it 'allows repo in different formats' do
      Slugbuilder::Builder.new(repo: 'https://github.com/jdlehman/node-js-sample.git', git_ref: 'master', stdout: StringIO.new) do |args|
        expect(args).to eq({repo: repo, git_ref: 'master', git_url: 'https://github.com/jdlehman/node-js-sample.git'})
      end
    end

    it 'allows overriding default git service' do
      Slugbuilder::Builder.new(repo: 'https://gitlab.com/jdlehman/node-js-sample.git', git_ref: 'master', stdout: StringIO.new) do |args|
        expect(args).to eq({repo: repo, git_ref: 'master', git_url: 'https://gitlab.com/jdlehman/node-js-sample.git'})
      end
    end

    it 'converts git urls to the specified protocol' do
      Slugbuilder::Builder.new(repo: 'git@gitlab.com:jdlehman/node-js-sample.git', git_ref: 'master', stdout: StringIO.new) do |args|
        expect(args).to eq({repo: repo, git_ref: 'master', git_url: 'https://gitlab.com/jdlehman/node-js-sample.git'})
      end
      Slugbuilder.config.protocol = 'ssh'
      Slugbuilder::Builder.new(repo: 'https://gitlab.com/jdlehman/node-js-sample.git', git_ref: 'master', stdout: StringIO.new) do |args|
        expect(args).to eq({repo: repo, git_ref: 'master', git_url: 'git@gitlab.com:jdlehman/node-js-sample.git'})
      end
    end
  end

  describe '#build' do
    let(:builder) { Slugbuilder::Builder.new(repo: repo, git_ref: 'master', stdout: StringIO.new) }

    it 'builds the slug' do
      builder.build
      expect(Dir['/tmp/slugs/*']).to include('/tmp/slugs/jdlehman.node-js-sample.master.8edb1341f89cdb692940c8aec9edb53edeaa1bad.tgz')
    end

    it 'allows setting the slug_name' do
      builder.build(slug_name: 'my_slug')
      expect(Dir['/tmp/slugs/*']).to include('/tmp/slugs/my_slug.tgz')
    end

    it 'allows setting the env' do
      builder.build(env: {TEST_ENV: 'something', ANOTHER_ONE: 3})
      expect(Dir['/tmp/slugbuilder/environment/*']).to eq(['/tmp/slugbuilder/environment/ANOTHER_ONE', '/tmp/slugbuilder/environment/TEST_ENV'])
      expect(IO.read('/tmp/slugbuilder/environment/TEST_ENV')).to eq('something')
      expect(IO.read('/tmp/slugbuilder/environment/ANOTHER_ONE')).to eq('3')
    end

    it 'creates environment dir on build' do
      builder.build
      expect(Dir['/tmp/slugbuilder/*']).to include('/tmp/slugbuilder/environment')
    end

    it 'allows building without the cache' do
      Slugbuilder.config.buildpacks = [
        'https://github.com/heroku/heroku-buildpack-nodejs.git',
        'https://github.com/heroku/heroku-buildpack-ruby.git'
      ]
      builder.build
      Slugbuilder.config.buildpacks = ['https://github.com/heroku/heroku-buildpack-nodejs.git']
      builder.build(clear_cache: true)
      # make sure that ruby buildpack is no longer cached
      expect(Dir['/tmp/slugbuilder-cache/buildpacks/*']).to eq(['/tmp/slugbuilder-cache/buildpacks/heroku__heroku-buildpack-nodejs'])
    end

    it 'allows specifying the buildpacks for a build' do
      builder.build
      expect(Dir['/tmp/slugbuilder-cache/buildpacks/*']).to eq(['/tmp/slugbuilder-cache/buildpacks/heroku__heroku-buildpack-nodejs'])
      buildpacks = [
        'https://github.com/heroku/heroku-buildpack-nodejs.git',
        'https://github.com/heroku/heroku-buildpack-ruby.git'
      ]
      builder.build(buildpacks: buildpacks)
      expect(Dir['/tmp/slugbuilder-cache/buildpacks/*']).to eq([
        '/tmp/slugbuilder-cache/buildpacks/heroku__heroku-buildpack-nodejs',
        '/tmp/slugbuilder-cache/buildpacks/heroku__heroku-buildpack-ruby'
      ])
    end

    it 'accepts different buildpack formats and versions' do
      buildpacks = [
        'heroku/heroku-buildpack-nodejs',
        'git@github.com:heroku/heroku-buildpack-ruby.git#5a1ca011c568321077101028a11d24e6e09f1c36'
      ]
      builder.build(buildpacks: buildpacks)
      expect(Dir['/tmp/slugbuilder-cache/buildpacks/*']).to eq([
        '/tmp/slugbuilder-cache/buildpacks/heroku__heroku-buildpack-nodejs',
        '/tmp/slugbuilder-cache/buildpacks/heroku__heroku-buildpack-ruby',
        '/tmp/slugbuilder-cache/buildpacks/heroku__heroku-buildpack-ruby5a1ca011c568321077101028a11d24e6e09f1c36'
      ])
    end

    it 'accepts a prebuild Proc' do
      # conforms to `call` API of a proc
      # but a proc will work here too
      class Prebuilder
        def self.call(args)
          expect(args).to eq({repo: repo, git_ref: 'master'})
        end
      end
      builder.build(prebuild: Prebuilder)
    end

    it 'accepts a postbuild Proc' do
      my_proc = ->(args) do
        expect(args.keys).to include(:repo, :git_ref, :git_sha, :request_id, :stats, :slug)
      end
      builder.build(postbuild: my_proc)
    end

    it 'accepts a postbuild block' do
      builder.build do |args|
        expect(args.keys).to include(:repo, :git_ref, :git_sha, :request_id, :stats, :slug)
      end
    end

    it 'runs pre-compile and post-compile script if present' do
      builder.build
      expect(Dir['/tmp/slugbuilder/jdlehman/node-js-sample/master/*']).to include(
        '/tmp/slugbuilder/jdlehman/node-js-sample/master/pre-compile-success',
        '/tmp/slugbuilder/jdlehman/node-js-sample/master/post-compile-success'
      )
    end
  end
end
