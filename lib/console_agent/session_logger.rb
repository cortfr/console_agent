module ConsoleAgent
  module SessionLogger
    class << self
      def log(attrs)
        return unless ConsoleAgent.configuration.session_logging
        return unless table_exists?

        record = session_class.create!(
          query:         attrs[:query],
          conversation:  Array(attrs[:conversation]).to_json,
          input_tokens:  attrs[:input_tokens] || 0,
          output_tokens: attrs[:output_tokens] || 0,
          user_name:     current_user_name,
          mode:          attrs[:mode].to_s,
          code_executed: attrs[:code_executed],
          code_output:   attrs[:code_output],
          code_result:   attrs[:code_result],
          console_output: attrs[:console_output],
          executed:      attrs[:executed] || false,
          provider:      ConsoleAgent.configuration.provider.to_s,
          model:         ConsoleAgent.configuration.resolved_model,
          duration_ms:   attrs[:duration_ms],
          created_at:    Time.respond_to?(:current) ? Time.current : Time.now
        )
        record.id
      rescue => e
        msg = "ConsoleAgent: session logging failed: #{e.class}: #{e.message}"
        $stderr.puts "\e[33m#{msg}\e[0m" if $stderr.respond_to?(:puts)
        ConsoleAgent.logger.warn(msg)
        nil
      end

      def update(id, attrs)
        return unless id
        return unless ConsoleAgent.configuration.session_logging
        return unless table_exists?

        updates = {}
        updates[:conversation]  = Array(attrs[:conversation]).to_json if attrs.key?(:conversation)
        updates[:input_tokens]  = attrs[:input_tokens]  if attrs.key?(:input_tokens)
        updates[:output_tokens] = attrs[:output_tokens] if attrs.key?(:output_tokens)
        updates[:code_executed] = attrs[:code_executed]  if attrs.key?(:code_executed)
        updates[:code_output]   = attrs[:code_output]    if attrs.key?(:code_output)
        updates[:code_result]   = attrs[:code_result]    if attrs.key?(:code_result)
        updates[:console_output] = attrs[:console_output] if attrs.key?(:console_output)
        updates[:executed]      = attrs[:executed]       if attrs.key?(:executed)
        updates[:duration_ms]   = attrs[:duration_ms]    if attrs.key?(:duration_ms)

        session_class.where(id: id).update_all(updates) unless updates.empty?
      rescue => e
        msg = "ConsoleAgent: session update failed: #{e.class}: #{e.message}"
        $stderr.puts "\e[33m#{msg}\e[0m" if $stderr.respond_to?(:puts)
        ConsoleAgent.logger.warn(msg)
        nil
      end

      private

      def table_exists?
        # Only cache positive results — retry on failure so transient
        # errors (boot timing, connection not ready) don't stick forever
        return true if @table_exists
        @table_exists = session_class.connection.table_exists?('console_agent_sessions')
      rescue
        false
      end

      def session_class
        Object.const_get('ConsoleAgent::Session')
      end

      def current_user_name
        ConsoleAgent.current_user || ENV['USER']
      end
    end
  end
end
