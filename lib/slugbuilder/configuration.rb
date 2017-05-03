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
    attr_accessor :base_dir, :cache_dir, :output_dir,
      :git_service, :buildpacks, :protocol

    def initialize
      @base_dir = '/tmp/slugbuilder'
      @cache_dir = '/tmp/slugbuilder-cache'
      @output_dir = '.'
      @git_service = 'github.com'
      @protocol = 'https'
      @buildpacks = []
    end
  end
end
