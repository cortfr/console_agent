module ConsoleAgent
  module Providers
    class Anthropic < Base
      API_URL = 'https://api.anthropic.com'.freeze

      def chat(messages, system_prompt: nil)
        conn = build_connection(API_URL, {
          'x-api-key' => config.resolved_api_key,
          'anthropic-version' => '2023-06-01'
        })

        body = {
          model: config.resolved_model,
          max_tokens: config.max_tokens,
          temperature: config.temperature,
          messages: format_messages(messages)
        }
        body[:system] = system_prompt if system_prompt

        data = parse_response(conn.post('/v1/messages', JSON.generate(body)))
        extract_text(data)
      end

      private

      def format_messages(messages)
        messages.map do |msg|
          { role: msg[:role].to_s, content: msg[:content].to_s }
        end
      end

      def extract_text(data)
        content = data['content']
        return '' unless content.is_a?(Array)

        content.select { |c| c['type'] == 'text' }
               .map { |c| c['text'] }
               .join("\n")
      end
    end
  end
end
