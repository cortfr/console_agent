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

    def status
      c = configuration
      key = c.resolved_api_key
      masked_key = if key.nil? || key.empty?
                     "\e[31m(not set)\e[0m"
                   else
                     key[0..6] + '...' + key[-4..-1]
                   end

      lines = []
      lines << "\e[36m[ConsoleAgent v#{VERSION}]\e[0m"
      lines << "  Provider:       #{c.provider}"
      lines << "  Model:          #{c.resolved_model}"
      lines << "  API key:        #{masked_key}"
      lines << "  Context mode:   #{c.context_mode}"
      lines << "  Max tokens:     #{c.max_tokens}"
      lines << "  Temperature:    #{c.temperature}"
      lines << "  Timeout:        #{c.timeout}s"
      lines << "  Max tool rounds:#{c.max_tool_rounds}" if c.context_mode == :smart
      lines << "  Auto-execute:   #{c.auto_execute}"
      lines << "  Debug:          #{c.debug}"
      $stdout.puts lines.join("\n")
      nil
    end
  end
end

require 'console_agent/railtie' if defined?(Rails::Railtie)
