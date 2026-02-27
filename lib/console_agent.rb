require 'console_agent/version'
require 'console_agent/configuration'

module ConsoleAgent
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def logger
      @logger ||= if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
                    Rails.logger
                  else
                    require 'logger'
                    Logger.new($stderr, progname: 'ConsoleAgent')
                  end
    end

    def logger=(log)
      @logger = log
    end
  end
end

require 'console_agent/railtie' if defined?(Rails::Railtie)
