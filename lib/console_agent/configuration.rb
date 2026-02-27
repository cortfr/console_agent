module ConsoleAgent
  class Configuration
    PROVIDERS = %i[anthropic openai].freeze
    CONTEXT_MODES = %i[full smart].freeze

    attr_accessor :provider, :api_key, :model, :max_tokens,
                  :auto_execute, :context_mode, :temperature,
                  :timeout, :debug, :max_tool_rounds

    def initialize
      @provider     = :anthropic
      @api_key      = nil
      @model        = nil
      @max_tokens   = 4096
      @auto_execute = false
      @context_mode = :smart
      @temperature  = 0.2
      @timeout      = 30
      @debug        = false
      @max_tool_rounds = 10
    end

    def resolved_api_key
      return @api_key if @api_key && !@api_key.empty?

      case @provider
      when :anthropic
        ENV['ANTHROPIC_API_KEY']
      when :openai
        ENV['OPENAI_API_KEY']
      end
    end

    def resolved_model
      return @model if @model && !@model.empty?

      case @provider
      when :anthropic
        'claude-opus-4-6'
      when :openai
        'gpt-5.3-codex'
      end
    end

    def validate!
      unless PROVIDERS.include?(@provider)
        raise ConfigurationError, "Unknown provider: #{@provider}. Valid: #{PROVIDERS.join(', ')}"
      end

      unless resolved_api_key
        env_var = @provider == :anthropic ? 'ANTHROPIC_API_KEY' : 'OPENAI_API_KEY'
        raise ConfigurationError, "No API key. Set config.api_key or #{env_var} env var."
      end
    end
  end

  class ConfigurationError < StandardError; end
end
