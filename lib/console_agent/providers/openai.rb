module ConsoleAgent
  module Providers
    class OpenAI < Base
      API_URL = 'https://api.openai.com'.freeze

      def chat(messages, system_prompt: nil)
        conn = build_connection(API_URL, {
          'Authorization' => "Bearer #{config.resolved_api_key}"
        })

        formatted = []
        formatted << { role: 'system', content: system_prompt } if system_prompt
        formatted.concat(format_messages(messages))

        body = {
          model: config.resolved_model,
          max_tokens: config.max_tokens,
          temperature: config.temperature,
          messages: formatted
        }

        json_body = JSON.generate(body)
        debug_request("#{API_URL}/v1/chat/completions", body)
        response = conn.post('/v1/chat/completions', json_body)
        debug_response(response.body)
        data = parse_response(response)
        extract_text(data)
      end

      private

      def format_messages(messages)
        messages.map do |msg|
          { role: msg[:role].to_s, content: msg[:content].to_s }
        end
      end

      def extract_text(data)
        choices = data['choices']
        return '' unless choices.is_a?(Array) && !choices.empty?

        choices[0].dig('message', 'content') || ''
      end
    end
  end
end
