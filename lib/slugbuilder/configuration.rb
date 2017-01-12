module Slugbuilder
  class << self
    attr_accessor :config
  end

  def self.config
    @config ||= Configuration.new
  end

  def self.reset
    @config = Configuration.new
  end

  def self.configure
    yield(config)
  end

  class Configuration
    attr_accessor :base_dir, :cache_dir, :buildpacks, :upload_url

    def initialize
      @base_dir = '/tmp/slugbuilder'
      @upload_url = nil
      @cache_dir = '/tmp/slugbuilder-cache'
      @buildpacks = []
    end
  end
end
