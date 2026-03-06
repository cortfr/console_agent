module ConsoleAgent
  # Raised by safety guards to block dangerous operations.
  # Host apps should raise this error in their custom guards.
  # ConsoleAgent will catch it and guide the user to use 'd' or /danger.
  class SafetyError < StandardError; end

  class SafetyGuards
    attr_reader :guards

    def initialize
      @guards = {}
      @enabled = true
    end

    def add(name, &block)
      @guards[name.to_sym] = block
    end

    def remove(name)
      @guards.delete(name.to_sym)
    end

    def enabled?
      @enabled
    end

    def enable!
      @enabled = true
    end

    def disable!
      @enabled = false
    end

    def empty?
      @guards.empty?
    end

    def names
      @guards.keys
    end

    # Compose all guards around a block of code.
    # Each guard is an around-block: guard.call { inner }
    # Result: guard_1 { guard_2 { guard_3 { yield } } }
    def wrap(&block)
      return yield unless @enabled && !@guards.empty?

      @guards.values.reduce(block) { |inner, guard|
        -> { guard.call(&inner) }
      }.call
    end
  end

  # Built-in guard: database write prevention
  # Works on all Rails versions (5+) and all database adapters.
  # Prepends a write-intercepting module once, controlled by a thread-local flag.
  module BuiltinGuards
    # Blocks INSERT, UPDATE, DELETE, DROP, CREATE, ALTER, TRUNCATE
    module WriteBlocker
      WRITE_PATTERN = /\A\s*(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE)\b/i

      def execute(sql, *args, **kwargs)
        if Thread.current[:console_agent_block_writes] && sql.match?(WRITE_PATTERN)
          raise ConsoleAgent::SafetyError, "Database write blocked: #{sql.strip.split(/\s+/).first(3).join(' ')}..."
        end
        super
      end

      # Also intercept exec_delete/exec_update for adapters that bypass execute
      def exec_delete(sql, *args, **kwargs)
        if Thread.current[:console_agent_block_writes] && sql.match?(WRITE_PATTERN)
          raise ConsoleAgent::SafetyError, "Database write blocked: #{sql.strip.split(/\s+/).first(3).join(' ')}..."
        end
        super
      end

      def exec_update(sql, *args, **kwargs)
        if Thread.current[:console_agent_block_writes] && sql.match?(WRITE_PATTERN)
          raise ConsoleAgent::SafetyError, "Database write blocked: #{sql.strip.split(/\s+/).first(3).join(' ')}..."
        end
        super
      end
    end

    def self.database_writes
      ->(& block) {
        ensure_write_blocker_installed!
        Thread.current[:console_agent_block_writes] = true
        begin
          block.call
        ensure
          Thread.current[:console_agent_block_writes] = false
        end
      }
    end

    def self.ensure_write_blocker_installed!
      return if @write_blocker_installed

      connection = ActiveRecord::Base.connection
      unless connection.class.ancestors.include?(WriteBlocker)
        connection.class.prepend(WriteBlocker)
      end
      @write_blocker_installed = true
    end

    # Blocks non-safe HTTP requests (POST, PUT, PATCH, DELETE, etc.) via Net::HTTP.
    # Since most Ruby HTTP libraries (HTTParty, RestClient, Faraday) use Net::HTTP
    # under the hood, this covers them all.
    module HttpBlocker
      SAFE_METHODS = %w[GET HEAD OPTIONS TRACE].freeze

      def request(req, *args, &block)
        if Thread.current[:console_agent_block_http] && !SAFE_METHODS.include?(req.method)
          raise ConsoleAgent::SafetyError, "HTTP #{req.method} blocked (#{@address}#{req.path})"
        end
        super
      end
    end

    def self.http_mutations
      ->(&block) {
        ensure_http_blocker_installed!
        Thread.current[:console_agent_block_http] = true
        begin
          block.call
        ensure
          Thread.current[:console_agent_block_http] = false
        end
      }
    end

    def self.mailers
      ->(&block) {
        old_value = ActionMailer::Base.perform_deliveries
        ActionMailer::Base.perform_deliveries = false
        begin
          block.call
        ensure
          ActionMailer::Base.perform_deliveries = old_value
        end
      }
    end

    def self.ensure_http_blocker_installed!
      return if @http_blocker_installed

      require 'net/http'
      unless Net::HTTP.ancestors.include?(HttpBlocker)
        Net::HTTP.prepend(HttpBlocker)
      end
      @http_blocker_installed = true
    end
  end
end
