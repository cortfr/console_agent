module ConsoleAgent
  class Repl
    def initialize(binding_context)
      @binding_context = binding_context
      @executor = Executor.new(binding_context)
      @provider = nil
      @context = nil
      @history = []
    end

    def one_shot(query)
      response = send_query(query)
      code = @executor.display_response(response)
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
      response = send_query(query)
      @executor.display_response(response)
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

      loop do
        $stdout.print "\e[33mai> \e[0m"
        input = $stdin.gets
        break if input.nil?

        input = input.strip
        break if input.downcase == 'exit' || input.downcase == 'quit'
        next if input.empty?

        @history << { role: :user, content: input }

        response = send_query(input, conversation: @history)
        code = @executor.display_response(response)

        @history << { role: :assistant, content: response }

        if code && !code.strip.empty?
          if ConsoleAgent.configuration.auto_execute
            result = @executor.execute(code)
          else
            result = @executor.confirm_and_execute(code)
          end

          if result
            result_str = result.inspect
            result_str = result_str[0..500] + '...' if result_str.length > 500
            @history << { role: :user, content: "Execution result: #{result_str}" }
          end
        end
      end

      $stdout.puts "\e[36mLeft ConsoleAgent interactive mode.\e[0m"
    rescue Interrupt
      $stdout.puts "\n\e[36mLeft ConsoleAgent interactive mode.\e[0m"
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
  end
end
