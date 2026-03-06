require 'console_agent/channel/base'

module ConsoleAgent
  module Channel
    class Slack < Base
      ANSI_REGEX = /\e\[[0-9;]*m/

      def initialize(slack_bot:, channel_id:, thread_ts:, user_name: nil)
        @slack_bot = slack_bot
        @channel_id = channel_id
        @thread_ts = thread_ts
        @user_name = user_name
        @reply_queue = Queue.new
        @cancelled = false
        @log_prefix = "[#{@channel_id}/#{@thread_ts}] @#{@user_name}"
        @output_log = StringIO.new
      end

      def cancel!
        @cancelled = true
      end

      def cancelled?
        @cancelled
      end

      def display(text)
        post(strip_ansi(text))
      end

      def display_dim(text)
        post(strip_ansi(text))
      end

      def display_warning(text)
        post(":warning: #{strip_ansi(text)}")
      end

      def display_error(text)
        post(":x: #{strip_ansi(text)}")
      end

      def display_code(code)
        post("```#{strip_ansi(code)}```")
      end

      def display_result_output(output)
        text = strip_ansi(output).strip
        return if text.empty?
        text = text[0, 3000] + "\n... (truncated)" if text.length > 3000
        post("```#{text}```")
      end

      def display_result(result)
        return if result.nil?
        text = "=> #{result.inspect}"
        if text.length > 3000
          text = text[0, 3000] + "\n... (truncated)"
        end
        post("```#{strip_ansi(text)}```")
      end

      def prompt(text)
        post(strip_ansi(text))
        @reply_queue.pop
      end

      def confirm(_text)
        'y'
      end

      def user_identity
        @user_name
      end

      def mode
        'slack'
      end

      def supports_danger?
        false
      end

      def supports_editing?
        false
      end

      def wrap_llm_call(&block)
        yield
      end

      def log_input(text)
        @output_log.write("@#{@user_name}: #{text}\n")
      end

      # Called by SlackBot when a thread reply arrives
      def receive_reply(text)
        @output_log.write("@#{@user_name}: #{text}\n")
        @reply_queue.push(text)
      end

      def console_capture_string
        @output_log.string
      end

      private

      def post(text)
        return if text.nil? || text.strip.empty?
        @output_log.write("#{text}\n")
        $stdout.puts "#{@log_prefix} >> #{truncate_log(text)}"
        @slack_bot.send(:post_message,
          channel: @channel_id,
          thread_ts: @thread_ts,
          text: text
        )
      rescue => e
        ConsoleAgent.logger.error("Slack post failed: #{e.message}")
      end

      def truncate_log(text)
        flat = text.to_s.gsub("\n", "\\n")
        flat.length > 200 ? flat[0, 200] + "..." : flat
      end

      def strip_ansi(text)
        text.to_s.gsub(ANSI_REGEX, '')
      end
    end
  end
end
