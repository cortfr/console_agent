require 'console_agent/version'
require 'console_agent/configuration'

module ConsoleAgent
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def reset_configuration!
      @configuration = Configuration.new
      reset_storage!
    end

    def storage
      @storage ||= begin
        adapter = configuration.storage_adapter
        if adapter
          adapter
        else
          require 'console_agent/storage/file_storage'
          Storage::FileStorage.new
        end
      end
    end

    def reset_storage!
      @storage = nil
    end

    def logger
      @logger ||= if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
                    Rails.logger
                  else
                    require 'logger'
                    Logger.new($stderr, progname: 'ConsoleAgent')
                  end
    end

    def logger=(log)
      @logger = log
    end

    def current_user
      @current_user
    end

    def current_user=(name)
      @current_user = name
    end

    def status
      c = configuration
      key = c.resolved_api_key
      masked_key = if key.nil? || key.empty?
                     "\e[31m(not set)\e[0m"
                   else
                     key[0..6] + '...' + key[-4..-1]
                   end

      lines = []
      lines << "\e[36m[ConsoleAgent v#{VERSION}]\e[0m"
      lines << "  Provider:       #{c.provider}"
      lines << "  Model:          #{c.resolved_model}"
      lines << "  API key:        #{masked_key}"
      lines << "  Max tokens:     #{c.max_tokens}"
      lines << "  Temperature:    #{c.temperature}"
      lines << "  Timeout:        #{c.timeout}s"
      lines << "  Max tool rounds:#{c.max_tool_rounds}"
      lines << "  Auto-execute:   #{c.auto_execute}"
      lines << "  Memories:       #{c.memories_enabled}"
      lines << "  Session logging:#{session_table_status}"
      lines << "  Debug:          #{c.debug}"
      $stdout.puts lines.join("\n")
      nil
    end

    def setup!
      conn = session_connection
      table = 'console_agent_sessions'

      if conn.table_exists?(table)
        $stdout.puts "\e[32mConsoleAgent: #{table} already exists. Run ConsoleAgent.teardown! first to recreate.\e[0m"
      else
        conn.create_table(table) do |t|
          t.text    :query,         null: false
          t.text    :conversation,  null: false
          t.integer :input_tokens,  default: 0
          t.integer :output_tokens, default: 0
          t.string  :user_name,     limit: 255
          t.string  :mode,          limit: 20, null: false
          t.text    :code_executed
          t.text    :code_output
          t.text    :code_result
          t.text    :console_output
          t.boolean :executed,      default: false
          t.string  :provider,      limit: 50
          t.string  :model,         limit: 100
          t.string  :name,          limit: 255
          t.integer :duration_ms
          t.datetime :created_at,   null: false
        end

        conn.add_index(table, :created_at)
        conn.add_index(table, :user_name)
        conn.add_index(table, :name)

        $stdout.puts "\e[32mConsoleAgent: created #{table} table.\e[0m"
      end
    rescue => e
      $stderr.puts "\e[31mConsoleAgent setup failed: #{e.class}: #{e.message}\e[0m"
    end

    def migrate!
      conn = session_connection
      table = 'console_agent_sessions'

      unless conn.table_exists?(table)
        $stderr.puts "\e[33mConsoleAgent: #{table} does not exist. Run ConsoleAgent.setup! first.\e[0m"
        return
      end

      migrations = []

      unless conn.column_exists?(table, :name)
        conn.add_column(table, :name, :string, limit: 255)
        conn.add_index(table, :name) unless conn.index_exists?(table, :name)
        migrations << 'name'
      end

      if migrations.empty?
        $stdout.puts "\e[32mConsoleAgent: #{table} is up to date.\e[0m"
      else
        $stdout.puts "\e[32mConsoleAgent: added columns: #{migrations.join(', ')}.\e[0m"
      end
    rescue => e
      $stderr.puts "\e[31mConsoleAgent migrate failed: #{e.class}: #{e.message}\e[0m"
    end

    def teardown!
      conn = session_connection
      table = 'console_agent_sessions'

      unless conn.table_exists?(table)
        $stdout.puts "\e[33mConsoleAgent: #{table} does not exist, nothing to remove.\e[0m"
        return
      end

      count = conn.select_value("SELECT COUNT(*) FROM #{conn.quote_table_name(table)}")
      $stdout.print "\e[33mDrop #{table} (#{count} sessions)? [y/N] \e[0m"
      answer = $stdin.gets.to_s.strip.downcase

      unless answer == 'y' || answer == 'yes'
        $stdout.puts "\e[33mCancelled.\e[0m"
        return
      end

      conn.drop_table(table)
      $stdout.puts "\e[32mConsoleAgent: dropped #{table}.\e[0m"
    rescue => e
      $stderr.puts "\e[31mConsoleAgent teardown failed: #{e.class}: #{e.message}\e[0m"
    end

    private

    def session_table_status
      return 'disabled' unless configuration.session_logging
      conn = session_connection
      if conn.table_exists?('console_agent_sessions')
        count = conn.select_value("SELECT COUNT(*) FROM #{conn.quote_table_name('console_agent_sessions')}")
        "\e[32m#{count} sessions\e[0m"
      else
        "\e[33mtable missing (run ConsoleAgent.setup!)\e[0m"
      end
    rescue
      "\e[33munavailable\e[0m"
    end

    def session_connection
      klass = configuration.connection_class
      if klass
        klass = Object.const_get(klass) if klass.is_a?(String)
        klass.connection
      else
        ActiveRecord::Base.connection
      end
    end
  end
end

if defined?(Rails::Railtie)
  require 'console_agent/railtie'
  require 'console_agent/engine'
end
