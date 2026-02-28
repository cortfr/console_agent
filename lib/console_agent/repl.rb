require 'readline'

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
      @input_history = []
    end

    def one_shot(query)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = send_query(query)
      track_usage(result)
      code = @executor.display_response(result.text)
      display_usage(result)

      exec_result = nil
      executed = false
      has_code = code && !code.strip.empty?

      if has_code
        exec_result = if ConsoleAgent.configuration.auto_execute
                        @executor.execute(code)
                      else
                        @executor.confirm_and_execute(code)
                      end
        executed = !@executor.last_cancelled?
      end

      log_session(
        query: query,
        conversation: [{ role: :user, content: query }, { role: :assistant, content: result.text }],
        mode: 'one_shot',
        code_executed: has_code ? code : nil,
        code_output: executed ? @executor.last_output : nil,
        code_result: executed && exec_result ? exec_result.inspect : nil,
        executed: executed,
        start_time: start_time
      )

      exec_result
    rescue Providers::ProviderError => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.message}\e[0m"
      nil
    rescue => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.class}: #{e.message}\e[0m"
      nil
    end

    def explain(query)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = send_query(query)
      track_usage(result)
      @executor.display_response(result.text)
      display_usage(result)

      log_session(
        query: query,
        conversation: [{ role: :user, content: query }, { role: :assistant, content: result.text }],
        mode: 'explain',
        executed: false,
        start_time: start_time
      )

      nil
    rescue Providers::ProviderError => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.message}\e[0m"
      nil
    rescue => e
      $stderr.puts "\e[31mConsoleAgent Error: #{e.class}: #{e.message}\e[0m"
      nil
    end

    def interactive
      @interactive_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      auto = ConsoleAgent.configuration.auto_execute
      $stdout.puts "\e[36mConsoleAgent interactive mode. Type 'exit' or 'quit' to leave.\e[0m"
      $stdout.puts "\e[2m  Auto-execute: #{auto ? 'ON' : 'OFF'} (Shift-Tab to toggle)\e[0m"

      # Bind Shift-Tab to insert /auto command and submit
      Readline.parse_and_bind('"\e[Z": "\C-a\C-k/auto\C-m"')

      @history = []
      @total_input_tokens = 0
      @total_output_tokens = 0
      @interactive_query = nil
      @interactive_session_id = nil
      @last_interactive_code = nil
      @last_interactive_output = nil
      @last_interactive_result = nil
      @last_interactive_executed = false

      loop do
        input = Readline.readline("\e[33mai> \e[0m", false)
        break if input.nil? # Ctrl-D

        input = input.strip
        break if input.downcase == 'exit' || input.downcase == 'quit'
        next if input.empty?

        if input == '/auto'
          ConsoleAgent.configuration.auto_execute = !ConsoleAgent.configuration.auto_execute
          mode = ConsoleAgent.configuration.auto_execute ? 'ON' : 'OFF'
          $stdout.puts "\e[36m  Auto-execute: #{mode}\e[0m"
          next
        end

        # Add to Readline history (avoid consecutive duplicates)
        Readline::HISTORY.push(input) unless input == Readline::HISTORY.to_a.last

        @interactive_query ||= input
        @history << { role: :user, content: input }

        # Save immediately so the session is visible in the admin UI while the AI thinks
        log_interactive_turn

        begin
          result = send_query(input, conversation: @history)
        rescue Interrupt
          $stdout.puts "\n\e[33m  Aborted.\e[0m"
          @history.pop # Remove the user message that never got a response
          log_interactive_turn
          next
        end

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

          unless @executor.last_cancelled?
            @last_interactive_code = code
            @last_interactive_output = @executor.last_output
            @last_interactive_result = exec_result ? exec_result.inspect : nil
            @last_interactive_executed = true
          end

          if @executor.last_cancelled?
            @history << { role: :user, content: "User declined to execute the code." }
          else
            output_parts = []

            # Capture printed output (puts, print, etc.)
            if @executor.last_output && !@executor.last_output.strip.empty?
              output_parts << "Output:\n#{@executor.last_output.strip}"
            end

            # Capture return value
            if exec_result
              output_parts << "Return value: #{exec_result.inspect}"
            end

            unless output_parts.empty?
              result_str = output_parts.join("\n\n")
              result_str = result_str[0..1000] + '...' if result_str.length > 1000
              @history << { role: :user, content: "Code was executed. #{result_str}" }
            end
          end
        end

        # Update with the AI response, tokens, and any execution results
        log_interactive_turn
      end

      finish_interactive_session
      display_session_summary
      $stdout.puts "\e[36mLeft ConsoleAgent interactive mode.\e[0m"
    rescue Interrupt
      # Ctrl-C during Readline input — exit cleanly
      $stdout.puts
      finish_interactive_session
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

      exhausted = false

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
            cached_tag = tools.last_cached? ? " (cached)" : ""
            $stdout.puts "\e[2m     #{preview}#{cached_tag}\e[0m"
          end

          if ConsoleAgent.configuration.debug
            $stderr.puts "\e[35m[debug tool result] #{tool_result}\e[0m"
          end

          messages << provider.format_tool_result(tc[:id], tool_result)
        end

        exhausted = true if round == max_rounds - 1
      end

      # If we hit the tool round limit, force a final response without tools
      if exhausted
        $stdout.puts "\e[33m  Hit tool round limit (#{max_rounds}). Forcing final answer. Increase with: ConsoleAgent.configure { |c| c.max_tool_rounds = 200 }\e[0m"
        messages << { role: :user, content: "You've used all available tool rounds. Please provide your best answer now based on what you've learned so far." }
        result = provider.chat(messages, system_prompt: context)
        total_input += result.input_tokens || 0
        total_output += result.output_tokens || 0
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
      when 'save_memory'
        "(\"#{args['name']}\")"
      when 'delete_memory'
        "(\"#{args['name']}\")"
      when 'recall_memories'
        args['query'] ? "(\"#{args['query']}\")" : ''
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
      when 'save_memory'
        (result.start_with?('Memory saved') || result.start_with?('Memory updated')) ? result : truncate(result, 80)
      when 'delete_memory'
        result.start_with?('Memory deleted') ? result : truncate(result, 80)
      when 'recall_memories'
        chunks = result.split("\n\n")
        chunks.length > 1 ? "#{chunks.length} memories found" : truncate(result, 80)
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

    def log_interactive_turn
      require 'console_agent/session_logger'
      session_attrs = {
        conversation:  @history,
        input_tokens:  @total_input_tokens,
        output_tokens: @total_output_tokens,
        code_executed: @last_interactive_code,
        code_output:   @last_interactive_output,
        code_result:   @last_interactive_result,
        executed:      @last_interactive_executed
      }

      if @interactive_session_id
        SessionLogger.update(@interactive_session_id, session_attrs)
      else
        @interactive_session_id = SessionLogger.log(
          session_attrs.merge(
            query: @interactive_query || '(interactive session)',
            mode:  'interactive'
          )
        )
      end
    end

    def finish_interactive_session
      require 'console_agent/session_logger'
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @interactive_start) * 1000).round
      if @interactive_session_id
        SessionLogger.update(@interactive_session_id,
          conversation:  @history,
          input_tokens:  @total_input_tokens,
          output_tokens: @total_output_tokens,
          code_executed: @last_interactive_code,
          code_output:   @last_interactive_output,
          code_result:   @last_interactive_result,
          executed:      @last_interactive_executed,
          duration_ms:   duration_ms
        )
      elsif @interactive_query
        # Session was never created (e.g., only one turn that failed to log)
        log_session(
          query: @interactive_query,
          conversation: @history,
          mode: 'interactive',
          code_executed: @last_interactive_code,
          code_output: @last_interactive_output,
          code_result: @last_interactive_result,
          executed: @last_interactive_executed,
          start_time: @interactive_start
        )
      end
    end

    def log_session(attrs)
      require 'console_agent/session_logger'
      start_time = attrs.delete(:start_time)
      duration_ms = if start_time
                      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
                    end
      SessionLogger.log(
        attrs.merge(
          input_tokens: @total_input_tokens,
          output_tokens: @total_output_tokens,
          duration_ms: duration_ms
        )
      )
    end

    def display_session_summary
      return if @total_input_tokens == 0 && @total_output_tokens == 0

      $stdout.puts "\e[2m[session totals — in: #{@total_input_tokens} | out: #{@total_output_tokens} | total: #{@total_input_tokens + @total_output_tokens}]\e[0m"
    end
  end
end
