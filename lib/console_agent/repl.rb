module ConsoleAgent
  class Repl
    def initialize(binding_context)
      @binding_context = binding_context
      @executor = Executor.new(binding_context)
      @provider = nil
      @context_builder = nil
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

    def context_builder
      @context_builder ||= ContextBuilder.new
    end

    def context
      @context ||= context_builder.build
    end

    def send_query(query, conversation: nil)
      ConsoleAgent.configuration.validate!

      messages = if conversation
                   conversation.map { |m| { role: m[:role], content: m[:content] } }
                 else
                   [{ role: :user, content: query }]
                 end

      if ConsoleAgent.configuration.context_mode == :smart
        send_query_with_tools(messages)
      else
        provider.chat(messages, system_prompt: context)
      end
    end

    def send_query_with_tools(messages)
      require 'console_agent/tools/registry'
      tools = Tools::Registry.new
      max_rounds = ConsoleAgent.configuration.max_tool_rounds
      total_input = 0
      total_output = 0
      result = nil

      max_rounds.times do |round|
        if round == 0
          $stdout.puts "\e[2m  Thinking...\e[0m"
        end

        result = provider.chat_with_tools(messages, tools: tools, system_prompt: context)
        total_input += result.input_tokens || 0
        total_output += result.output_tokens || 0

        break unless result.tool_use?

        # Show what the LLM is thinking (if it returned text alongside tool calls)
        if result.text && !result.text.strip.empty?
          $stdout.puts "\e[2m  #{result.text.strip}\e[0m"
        end

        # Add assistant message with tool calls to conversation
        messages << provider.format_assistant_message(result)

        # Execute each tool and show progress
        result.tool_calls.each do |tc|
          # ask_user handles its own display (prompt + input)
          if tc[:name] == 'ask_user'
            tool_result = tools.execute(tc[:name], tc[:arguments])
          else
            args_display = format_tool_args(tc[:name], tc[:arguments])
            $stdout.puts "\e[33m  -> #{tc[:name]}#{args_display}\e[0m"

            tool_result = tools.execute(tc[:name], tc[:arguments])

            preview = compact_tool_result(tc[:name], tool_result)
            $stdout.puts "\e[2m     #{preview}\e[0m"
          end

          if ConsoleAgent.configuration.debug
            $stderr.puts "\e[35m[debug tool result] #{tool_result}\e[0m"
          end

          messages << provider.format_tool_result(tc[:id], tool_result)
        end
      end

      Providers::ChatResult.new(
        text: result ? result.text : '',
        input_tokens: total_input,
        output_tokens: total_output,
        stop_reason: result ? result.stop_reason : :end_turn
      )
    end

    def format_tool_args(name, args)
      return '' if args.nil? || args.empty?

      case name
      when 'describe_table'
        "(\"#{args['table_name']}\")"
      when 'describe_model'
        "(\"#{args['model_name']}\")"
      when 'read_file'
        "(\"#{args['path']}\")"
      when 'search_code'
        dir = args['directory'] ? ", dir: \"#{args['directory']}\"" : ''
        "(\"#{args['query']}\"#{dir})"
      when 'list_files'
        args['directory'] ? "(\"#{args['directory']}\")" : ''
      else
        ''
      end
    end

    def compact_tool_result(name, result)
      return '(empty)' if result.nil? || result.strip.empty?

      case name
      when 'list_tables'
        tables = result.split(', ')
        if tables.length > 8
          "#{tables.length} tables: #{tables.first(8).join(', ')}..."
        else
          "#{tables.length} tables: #{result}"
        end
      when 'list_models'
        lines = result.split("\n")
        if lines.length > 6
          "#{lines.length} models: #{lines.first(6).map { |l| l.split(' ').first }.join(', ')}..."
        else
          "#{lines.length} models"
        end
      when 'describe_table'
        col_count = result.scan(/^\s{2}\S/).length
        "#{col_count} columns"
      when 'describe_model'
        parts = []
        assoc_count = result.scan(/^\s{2}(has_many|has_one|belongs_to|has_and_belongs_to_many)/).length
        val_count = result.scan(/^\s{2}(presence|uniqueness|format|length|numericality|inclusion|exclusion|confirmation|acceptance)/).length
        parts << "#{assoc_count} associations" if assoc_count > 0
        parts << "#{val_count} validations" if val_count > 0
        parts.empty? ? truncate(result, 80) : parts.join(', ')
      when 'list_files'
        lines = result.split("\n")
        "#{lines.length} files"
      when 'read_file'
        lines = result.split("\n")
        "#{lines.length} lines"
      when 'search_code'
        if result.start_with?('Found')
          result.split("\n").first
        elsif result.start_with?('No matches')
          result
        else
          truncate(result, 80)
        end
      else
        truncate(result, 80)
      end
    end

    def truncate(str, max)
      str.length > max ? str[0..max] + '...' : str
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
