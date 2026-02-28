require 'json'

module ConsoleAgent
  module Tools
    class Registry
      attr_reader :definitions

      # Tools that should never be cached (side effects or user interaction)
      NO_CACHE = %w[ask_user save_memory delete_memory execute_plan].freeze

      def initialize(executor: nil)
        @executor = executor
        @definitions = []
        @handlers = {}
        @cache = {}
        @last_cached = false
        register_all
      end

      def last_cached?
        @last_cached
      end

      def execute(tool_name, arguments = {})
        handler = @handlers[tool_name]
        unless handler
          return "Error: unknown tool '#{tool_name}'"
        end

        args = if arguments.is_a?(String)
                 begin
                   JSON.parse(arguments)
                 rescue
                   {}
                 end
               else
                 arguments || {}
               end

        unless NO_CACHE.include?(tool_name)
          cache_key = [tool_name, args].hash
          if @cache.key?(cache_key)
            @last_cached = true
            return @cache[cache_key]
          end
        end

        @last_cached = false
        result = handler.call(args)
        @cache[[tool_name, args].hash] = result unless NO_CACHE.include?(tool_name)
        result
      rescue => e
        "Error executing #{tool_name}: #{e.message}"
      end

      def to_anthropic_format
        definitions.map do |d|
          tool = {
            'name' => d[:name],
            'description' => d[:description],
            'input_schema' => d[:parameters]
          }
          tool
        end
      end

      def to_openai_format
        definitions.map do |d|
          {
            'type' => 'function',
            'function' => {
              'name' => d[:name],
              'description' => d[:description],
              'parameters' => d[:parameters]
            }
          }
        end
      end

      private

      def register_all
        require 'console_agent/tools/schema_tools'
        require 'console_agent/tools/model_tools'
        require 'console_agent/tools/code_tools'

        schema = SchemaTools.new
        models = ModelTools.new
        code = CodeTools.new

        register(
          name: 'list_tables',
          description: 'List all database table names in this Rails app.',
          parameters: { 'type' => 'object', 'properties' => {} },
          handler: ->(_args) { schema.list_tables }
        )

        register(
          name: 'describe_table',
          description: 'Get column names and types for a specific database table.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'table_name' => { 'type' => 'string', 'description' => 'The database table name (e.g. "users")' }
            },
            'required' => ['table_name']
          },
          handler: ->(args) { schema.describe_table(args['table_name']) }
        )

        register(
          name: 'list_models',
          description: 'List all ActiveRecord model names with their association names.',
          parameters: { 'type' => 'object', 'properties' => {} },
          handler: ->(_args) { models.list_models }
        )

        register(
          name: 'describe_model',
          description: 'Get detailed info about a specific model: associations, validations, table name.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'model_name' => { 'type' => 'string', 'description' => 'The model class name (e.g. "User")' }
            },
            'required' => ['model_name']
          },
          handler: ->(args) { models.describe_model(args['model_name']) }
        )

        register(
          name: 'list_files',
          description: 'List Ruby files in a directory of this Rails app. Defaults to app/ directory.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'directory' => { 'type' => 'string', 'description' => 'Relative directory path (e.g. "app/models", "lib"). Defaults to "app".' }
            }
          },
          handler: ->(args) { code.list_files(args['directory']) }
        )

        register(
          name: 'read_file',
          description: 'Read the contents of a file in this Rails app. Capped at 200 lines.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'path' => { 'type' => 'string', 'description' => 'Relative file path (e.g. "app/models/user.rb")' }
            },
            'required' => ['path']
          },
          handler: ->(args) { code.read_file(args['path']) }
        )

        register(
          name: 'search_code',
          description: 'Search for a pattern in Ruby files. Returns matching lines with file paths.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'query' => { 'type' => 'string', 'description' => 'Search pattern (substring match)' },
              'directory' => { 'type' => 'string', 'description' => 'Relative directory to search in. Defaults to "app".' }
            },
            'required' => ['query']
          },
          handler: ->(args) { code.search_code(args['query'], args['directory']) }
        )

        register(
          name: 'ask_user',
          description: 'Ask the console user a clarifying question. Use this when you need specific information to write accurate code (e.g. which user they are, which record to target, what value to use). Do NOT generate placeholder values like YOUR_USER_ID — ask instead.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'question' => { 'type' => 'string', 'description' => 'The question to ask the user' }
            },
            'required' => ['question']
          },
          handler: ->(args) { ask_user(args['question']) }
        )

        register_memory_tools
        register_execute_plan
      end

      def register_memory_tools
        return unless ConsoleAgent.configuration.memories_enabled

        require 'console_agent/tools/memory_tools'
        memory = MemoryTools.new

        register(
          name: 'save_memory',
          description: 'Save a fact or pattern you learned about this codebase for future sessions. Use after discovering how something works (e.g. sharding, auth, custom business logic).',
          parameters: {
            'type' => 'object',
            'properties' => {
              'name' => { 'type' => 'string', 'description' => 'Short name for this memory (e.g. "Sharding architecture")' },
              'description' => { 'type' => 'string', 'description' => 'Detailed description of what you learned' },
              'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' }, 'description' => 'Optional tags (e.g. ["database", "sharding"])' }
            },
            'required' => ['name', 'description']
          },
          handler: ->(args) {
            memory.save_memory(name: args['name'], description: args['description'], tags: args['tags'] || [])
          }
        )

        register(
          name: 'delete_memory',
          description: 'Delete a memory by name.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'name' => { 'type' => 'string', 'description' => 'The memory name to delete (e.g. "Sharding architecture")' }
            },
            'required' => ['name']
          },
          handler: ->(args) { memory.delete_memory(name: args['name']) }
        )

        register(
          name: 'recall_memories',
          description: 'Search your saved memories about this codebase. Call with no args to list all, or pass a query/tag to filter.',
          parameters: {
            'type' => 'object',
            'properties' => {
              'query' => { 'type' => 'string', 'description' => 'Search term to filter by name, description, or tags' },
              'tag' => { 'type' => 'string', 'description' => 'Filter by a specific tag' }
            }
          },
          handler: ->(args) { memory.recall_memories(query: args['query'], tag: args['tag']) }
        )
      end

      def register_execute_plan
        return unless @executor

        register(
          name: 'execute_plan',
          description: 'Execute a multi-step plan. Each step has a description and Ruby code. The plan is shown to the user for approval, then each step is executed in order. After each step executes, its return value is stored as step1, step2, etc. Use these variables in later steps to reference earlier results (e.g. `token = step1`).',
          parameters: {
            'type' => 'object',
            'properties' => {
              'steps' => {
                'type' => 'array',
                'description' => 'Ordered list of steps to execute',
                'items' => {
                  'type' => 'object',
                  'properties' => {
                    'description' => { 'type' => 'string', 'description' => 'What this step does' },
                    'code' => { 'type' => 'string', 'description' => 'Ruby code to execute' }
                  },
                  'required' => %w[description code]
                }
              }
            },
            'required' => ['steps']
          },
          handler: ->(args) { execute_plan(args['steps'] || []) }
        )
      end

      def execute_plan(steps)
        return 'No steps provided.' if steps.nil? || steps.empty?

        auto = ConsoleAgent.configuration.auto_execute

        # Display full plan
        $stdout.puts
        $stdout.puts "\e[36m  Plan (#{steps.length} steps):\e[0m"
        steps.each_with_index do |step, i|
          $stdout.puts "\e[36m  #{i + 1}. #{step['description']}\e[0m"
          $stdout.puts highlight_plan_code(step['code'])
        end
        $stdout.puts

        # Ask for plan approval (unless auto-execute)
        skip_confirmations = auto
        unless auto
          $stdout.print "\e[33m  Accept plan? [y/N/a(uto)] \e[0m"
          answer = $stdin.gets.to_s.strip.downcase
          case answer
          when 'a', 'auto'
            skip_confirmations = true
          when 'y', 'yes'
            # proceed with per-step confirmation
          else
            $stdout.puts "\e[33m  Plan declined.\e[0m"
            feedback = ask_feedback("What would you like changed?")
            return "User declined the plan. Feedback: #{feedback}"
          end
        end

        # Execute steps one by one
        results = []
        steps.each_with_index do |step, i|
          $stdout.puts
          $stdout.puts "\e[36m  Step #{i + 1}/#{steps.length}: #{step['description']}\e[0m"
          $stdout.puts "\e[33m  # Code:\e[0m"
          $stdout.puts highlight_plan_code(step['code'])

          # Per-step confirmation (unless auto-execute or plan-level auto)
          unless skip_confirmations
            $stdout.print "\e[33m  Run? [y/N/edit] \e[0m"
            step_answer = $stdin.gets.to_s.strip.downcase

            case step_answer
            when 'e', 'edit'
              edited = edit_step_code(step['code'])
              if edited && edited != step['code']
                $stdout.puts "\e[33m  # Edited code:\e[0m"
                $stdout.puts highlight_plan_code(edited)
                $stdout.print "\e[33m  Run edited code? [y/N] \e[0m"
                confirm = $stdin.gets.to_s.strip.downcase
                unless confirm == 'y' || confirm == 'yes'
                  feedback = ask_feedback("What would you like changed?")
                  results << "Step #{i + 1}: User declined after edit. Feedback: #{feedback}"
                  break
                end
                step['code'] = edited
              end
            when 'y', 'yes'
              # proceed
            else
              feedback = ask_feedback("What would you like changed?")
              results << "Step #{i + 1}: User declined. Feedback: #{feedback}"
              break
            end
          end

          exec_result = @executor.execute(step['code'])
          # Make result available as step1, step2, etc. for subsequent steps
          @executor.binding_context.local_variable_set(:"step#{i + 1}", exec_result)
          output = @executor.last_output

          step_report = "Step #{i + 1} (#{step['description']}):\n"
          if output && !output.strip.empty?
            step_report += "Output: #{output.strip}\n"
          end
          step_report += "Return value: #{exec_result.inspect}"
          results << step_report
        end

        results.join("\n\n")
      end

      def highlight_plan_code(code)
        if coderay_available?
          CodeRay.scan(code, :ruby).terminal.gsub(/^/, '     ')
        else
          code.split("\n").map { |l| "     \e[37m#{l}\e[0m" }.join("\n")
        end
      end

      def edit_step_code(code)
        require 'tempfile'
        editor = ENV['EDITOR'] || 'vi'
        tmpfile = Tempfile.new(['console_agent_step', '.rb'])
        tmpfile.write(code)
        tmpfile.flush
        system("#{editor} #{tmpfile.path}")
        File.read(tmpfile.path).strip
      rescue => e
        $stderr.puts "\e[31m  Editor error: #{e.message}\e[0m"
        code
      ensure
        tmpfile.close! if tmpfile
      end

      def coderay_available?
        return @coderay_available unless @coderay_available.nil?
        @coderay_available = begin
          require 'coderay'
          true
        rescue LoadError
          false
        end
      end

      def ask_feedback(prompt)
        $stdout.print "\e[36m  #{prompt} > \e[0m"
        feedback = $stdin.gets
        return '(no feedback provided)' if feedback.nil?
        feedback.strip.empty? ? '(no feedback provided)' : feedback.strip
      end

      def ask_user(question)
        $stdout.puts "\e[36m  ? #{question}\e[0m"
        $stdout.print "\e[36m  > \e[0m"
        answer = $stdin.gets
        return '(no answer provided)' if answer.nil?
        answer.strip.empty? ? '(no answer provided)' : answer.strip
      end

      def register(name:, description:, parameters:, handler:)
        @definitions << {
          name: name,
          description: description,
          parameters: parameters
        }
        @handlers[name] = handler
      end
    end
  end
end
