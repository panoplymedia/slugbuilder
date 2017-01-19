require 'spec_helper'

describe Slugbuilder::Builder do
  repo = 'jdlehman/node-js-sample'

  before(:each) do
    Slugbuilder.configure do |config|
      config.base_dir = '/tmp/slugbuilder'
      config.cache_dir = '/tmp/slugbuilder-cache'
      config.output_dir = '/tmp/slugs'
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
        expect(args).to eq({repo: repo, git_ref: 'master'})
      end
    end
  end

  describe '#build' do
    let(:builder) { Slugbuilder::Builder.new(repo: repo, git_ref: 'master', stdout: StringIO.new) }

    it 'builds the slug' do
      builder.build
      expect(Dir['/tmp/slugs/*']).to include('/tmp/slugs/jdlehman.node-js-sample.master.01262b640c76f95c4aa95a0fb8cd44741d8cc5bc.tgz')
    end

    it 'allows setting the slug_name' do
      builder.build(slug_name: 'my_slug')
      expect(Dir['/tmp/slugs/*']).to include('/tmp/slugs/my_slug.tgz')
    end

    it 'allows setting the env' do
      builder.build(env: {TEST_ENV: 'something', ANOTHER_ONE: 3})
      expect(ENV['TEST_ENV']).to eq('something')
      expect(ENV['ANOTHER_ONE']).to eq('3')
    end

    it 'allows building without the cache' do
      builder.build(clear_cache: true)
      expect(Dir.exists?('/tmp/slugbuilder-cache')).to be(false)
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
        expect(args.keys).to include(:repo, :git_ref, :git_sha, :stats, :slug)
      end
      builder.build(postbuild: my_proc)
    end

    it 'accepts a postbuild block' do
      builder.build do |args|
        expect(args.keys).to include(:repo, :git_ref, :git_sha, :stats, :slug)
      end
    end
  end
end
