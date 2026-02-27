require 'json'

module ConsoleAgent
  module Tools
    class Registry
      attr_reader :definitions

      def initialize
        @definitions = []
        @handlers = {}
        register_all
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

        handler.call(args)
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
