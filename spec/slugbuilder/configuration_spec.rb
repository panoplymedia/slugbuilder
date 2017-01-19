require 'spec_helper'

describe Slugbuilder::Configuration do
  describe '.config' do
    it 'reads/writes to config' do
      Slugbuilder.config.base_dir = 'test'

      expect(Slugbuilder.config.base_dir).to eq 'test'
    end
  end

  describe '.reset' do
    it 'resets config' do
      Slugbuilder.config.base_dir = 'test'
      Slugbuilder.reset
      expect(Slugbuilder.config.base_dir).not_to eq 'test'
    end
  end

  describe '.configure' do
    it 'allows configuration in a block' do
      Slugbuilder.configure do |config|
        config.base_dir = 'test'
      end
      expect(Slugbuilder.config.base_dir).to eq 'test'
    end
  end

  describe '#initialize' do
    it 'sets default configs' do
      config = Slugbuilder::Configuration.new
      expect(config.base_dir).to eq '/tmp/slugbuilder'
      expect(config.cache_dir).to eq '/tmp/slugbuilder-cache'
      expect(config.output_dir).to eq '.'
      expect(config.git_service).to eq 'github.com'
      expect(config.buildpacks).to eq []
    end
  end
end
