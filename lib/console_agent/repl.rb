module ConsoleAgent
  class Repl
    def initialize(binding_context)
      @binding_context = binding_context
      @executor = Executor.new(binding_context)
      @provider = nil
      @context = nil
      @history = []
      @total_input_tokens = 0
      @total_output_tokens = 0
    end

    def one_shot(query)
      result = send_query(query)
      track_usage(result)
      code = @executor.display_response(result.text)
      display_usage(result)
      return nil if code.nil? || code.strip.empty?

      if ConsoleAgent.configuration.auto_execute
        @executor.execute(code)
      else
        @executor.confirm_and_execute(code)
      end
    rescue Providers::ProviderError => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.message}\e[0m"
      nil
    rescue => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.class}: #{e.message}\e[0m"
      nil
    end

    def explain(query)
      result = send_query(query)
      track_usage(result)
      @executor.display_response(result.text)
      display_usage(result)
      nil
    rescue Providers::ProviderError => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.message}\e[0m"
      nil
    rescue => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.class}: #{e.message}\e[0m"
      nil
    end

    def interactive
      $stdout.puts "\e[36mConsoleAgent interactive mode. Type 'exit' or 'quit' to leave.\e[0m"
      @history = []
      @total_input_tokens = 0
      @total_output_tokens = 0

      loop do
        $stdout.print "\e[33mai> \e[0m"
        input = $stdin.gets
        break if input.nil?

        input = input.strip
        break if input.downcase == 'exit' || input.downcase == 'quit'
        next if input.empty?

        @history << { role: :user, content: input }

        result = send_query(input, conversation: @history)
        track_usage(result)
        code = @executor.display_response(result.text)
        display_usage(result, show_session: true)

        @history << { role: :assistant, content: result.text }

        if code && !code.strip.empty?
          if ConsoleAgent.configuration.auto_execute
            exec_result = @executor.execute(code)
          else
            exec_result = @executor.confirm_and_execute(code)
          end

          if exec_result
            result_str = exec_result.inspect
            result_str = result_str[0..500] + '...' if result_str.length > 500
            @history << { role: :user, content: "Execution result: #{result_str}" }
          end
        end
      end

      display_session_summary
      $stdout.puts "\e[36mLeft ConsoleAgent interactive mode.\e[0m"
    rescue Interrupt
      $stdout.puts
      display_session_summary
      $stdout.puts "\e[36mLeft ConsoleAgent interactive mode.\e[0m"
    rescue => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.class}: #{e.message}\e[0m"
    end

    private

    def provider
      @provider ||= Providers.build
    end

    def context
      @context ||= ContextBuilder.new.build
    end

    def send_query(query, conversation: nil)
      ConsoleAgent.configuration.validate!

      messages = if conversation
                   conversation.map { |m| { role: m[:role], content: m[:content] } }
                 else
                   [{ role: :user, content: query }]
                 end

      provider.chat(messages, system_prompt: context)
    end

    def track_usage(result)
      @total_input_tokens += result.input_tokens || 0
      @total_output_tokens += result.output_tokens || 0
    end

    def display_usage(result, show_session: false)
      input  = result.input_tokens
      output = result.output_tokens
      return unless input || output

      parts = []
      parts << "in: #{input}" if input
      parts << "out: #{output}" if output
      parts << "total: #{result.total_tokens}"

      line = "\e[2m[tokens #{parts.join(' | ')}]\e[0m"

      if show_session && (@total_input_tokens + @total_output_tokens) > result.total_tokens
        line += "\e[2m [session: in: #{@total_input_tokens} | out: #{@total_output_tokens} | total: #{@total_input_tokens + @total_output_tokens}]\e[0m"
      end

      $stdout.puts line
    end

    def display_session_summary
      return if @total_input_tokens == 0 && @total_output_tokens == 0

      $stdout.puts "\e[2m[session totals — in: #{@total_input_tokens} | out: #{@total_output_tokens} | total: #{@total_input_tokens + @total_output_tokens}]\e[0m"
    end
  end
end
