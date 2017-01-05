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
    attr_accessor :base_dir, :cache_dir, :buildpack_dir

    def initialize
      @base_dir = '/tmp/slugbuilder'
      @cache_dir = '/tmp/slugbuilder-cache'
      @buildpack_dir = 'buildpacks'
    end
  end
end
