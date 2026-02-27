require 'faraday'
require 'json'

module ConsoleAgent
  module Providers
    class Base
      attr_reader :config

      def initialize(config = ConsoleAgent.configuration)
        @config = config
      end

      def chat(messages, system_prompt: nil)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end

      private

      def build_connection(url, headers = {})
        Faraday.new(url: url) do |f|
          f.options.timeout = config.timeout
          f.options.open_timeout = config.timeout
          f.headers.update(headers)
          f.headers['Content-Type'] = 'application/json'
          f.adapter Faraday.default_adapter
        end
      end

      def debug_request(url, body)
        return unless config.debug

        $stderr.puts "\e[33m--- ConsoleAgent DEBUG: REQUEST ---\e[0m"
        $stderr.puts "\e[33mURL: #{url}\e[0m"
        parsed = body.is_a?(String) ? JSON.parse(body) : body
        $stderr.puts "\e[33m#{JSON.pretty_generate(parsed)}\e[0m"
        $stderr.puts "\e[33m--- END REQUEST ---\e[0m"
      rescue => e
        $stderr.puts "\e[33m[debug] #{body}\e[0m"
      end

      def debug_response(body)
        return unless config.debug

        $stderr.puts "\e[36m--- ConsoleAgent DEBUG: RESPONSE ---\e[0m"
        parsed = body.is_a?(String) ? JSON.parse(body) : body
        $stderr.puts "\e[36m#{JSON.pretty_generate(parsed)}\e[0m"
        $stderr.puts "\e[36m--- END RESPONSE ---\e[0m"
      rescue => e
        $stderr.puts "\e[36m[debug] #{body}\e[0m"
      end

      def parse_response(response)
        unless response.success?
          body = begin
                   JSON.parse(response.body)
                 rescue
                   { 'error' => response.body }
                 end
          error_msg = body.dig('error', 'message') || body['error'] || response.body
          raise ProviderError, "API error (#{response.status}): #{error_msg}"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise ProviderError, "Failed to parse response: #{e.message}"
      end
    end

    class ProviderError < StandardError; end

    def self.build(config = ConsoleAgent.configuration)
      case config.provider
      when :anthropic
        require 'console_agent/providers/anthropic'
        Anthropic.new(config)
      when :openai
        require 'console_agent/providers/openai'
        OpenAI.new(config)
      else
        raise ConfigurationError, "Unknown provider: #{config.provider}"
      end
    end
  end
end
