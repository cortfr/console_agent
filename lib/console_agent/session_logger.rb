module ConsoleAgent
  module SessionLogger
    class << self
      def log(attrs)
        return unless ConsoleAgent.configuration.session_logging
        return unless table_exists?

        session_class.create!(
          query:         attrs[:query],
          conversation:  Array(attrs[:conversation]).to_json,
          input_tokens:  attrs[:input_tokens] || 0,
          output_tokens: attrs[:output_tokens] || 0,
          user_name:     current_user_name,
          mode:          attrs[:mode].to_s,
          code_executed: attrs[:code_executed],
          code_output:   attrs[:code_output],
          code_result:   attrs[:code_result],
          executed:      attrs[:executed] || false,
          provider:      ConsoleAgent.configuration.provider.to_s,
          model:         ConsoleAgent.configuration.resolved_model,
          duration_ms:   attrs[:duration_ms],
          created_at:    Time.respond_to?(:current) ? Time.current : Time.now
        )
      rescue => e
        msg = "ConsoleAgent: session logging failed: #{e.class}: #{e.message}"
        $stderr.puts "\e[33m#{msg}\e[0m" if $stderr.respond_to?(:puts)
        ConsoleAgent.logger.warn(msg)
        nil
      end

      private

      def table_exists?
        unless instance_variable_defined?(:@table_exists_checked)
          @table_exists_checked = true
          @table_exists = session_class.connection.table_exists?('console_agent_sessions')
        end
        @table_exists
      rescue
        @table_exists_checked = true
        @table_exists = false
      end

      def session_class
        @session_class ||= Object.const_get('ConsoleAgent::Session')
      end

      def current_user_name
        ENV['USER']
      end
    end
  end
end
