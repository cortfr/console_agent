module ConsoleAgent
  class ContextBuilder
    def initialize(config = ConsoleAgent.configuration)
      @config = config
    end

    def build
      case @config.context_mode
      when :smart
        build_smart
      else
        build_full
      end
    rescue => e
      ConsoleAgent.logger.warn("ConsoleAgent: context build error: #{e.message}")
      system_instructions + "\n\n" + environment_context
    end

    def build_full
      parts = []
      parts << system_instructions
      parts << environment_context
      parts << schema_context
      parts << models_context
      parts << routes_context
      parts.compact.join("\n\n")
    end

    def build_smart
      parts = []
      parts << smart_system_instructions
      parts << environment_context
      parts << memory_context
      parts.compact.join("\n\n")
    end

    private

    def smart_system_instructions
      <<~PROMPT.strip
        You are a Ruby on Rails console assistant. The user is in a `rails console` session.
        You help them query data, debug issues, and understand their application.

        You have tools available to introspect the app's database schema, models, and source code.
        Use them as needed to write accurate queries. For example, call list_tables to see what
        tables exist, then describe_table to get column details for the ones you need.

        You also have an ask_user tool to ask the console user clarifying questions. Use it when
        you need specific information to write accurate code — such as which user they are, which
        record to target, or what value to use.

        You have memory tools to persist what you learn across sessions:
        - save_memory: persist facts or procedures you learn about this codebase.
          If a memory with the same name already exists, it will be updated in place.
        - delete_memory: remove a memory by name
        - recall_memories: search your saved memories for details

        IMPORTANT: Check the Memories section below BEFORE answering. If a memory is relevant,
        use recall_memories to get full details and apply that knowledge to your answer.
        When you use a memory, mention it briefly (e.g. "Based on what I know about sharding...").
        When you discover important patterns about this app, save them as memories.

        RULES:
        - Give ONE concise answer. Do not offer multiple alternatives or variations.
        - Respond with a single ```ruby code block that directly answers the question.
        - Include a brief one-line explanation before the code block.
        - Use the app's actual model names, associations, and schema.
        - Prefer ActiveRecord query interface over raw SQL.
        - For destructive operations, add a comment warning.
        - NEVER use placeholder values like YOUR_USER_ID or YOUR_EMAIL in code. If you need
          a specific value from the user, call the ask_user tool to get it first.
        - Keep code concise and idiomatic.
        - Use tools to look up schema/model details rather than guessing column names.
      PROMPT
    end

    def system_instructions
      <<~PROMPT.strip
        You are a Ruby on Rails console assistant. The user is in a `rails console` session.
        You help them query data, debug issues, and understand their application.

        RULES:
        - Give ONE concise answer. Do not offer multiple alternatives or variations.
        - Respond with a single ```ruby code block that directly answers the question.
        - Include a brief one-line explanation before the code block.
        - Use the app's actual model names, associations, and schema.
        - Prefer ActiveRecord query interface over raw SQL.
        - For destructive operations, add a comment warning.
        - If the request is ambiguous, ask a clarifying question instead of guessing.
        - Keep code concise and idiomatic.
      PROMPT
    end

    def environment_context
      lines = ["## Environment"]
      lines << "- Ruby #{RUBY_VERSION}"
      lines << "- Rails #{Rails.version}" if defined?(Rails) && Rails.respond_to?(:version)

      if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
        adapter = ActiveRecord::Base.connection.adapter_name rescue 'unknown'
        lines << "- Database adapter: #{adapter}"
      end

      if defined?(Bundler)
        key_gems = %w[devise cancancan pundit sidekiq delayed_job resque
                      paperclip carrierwave activestorage shrine
                      pg mysql2 sqlite3 mongoid]
        loaded = key_gems.select { |g| Gem.loaded_specs.key?(g) }
        lines << "- Key gems: #{loaded.join(', ')}" unless loaded.empty?
      end

      lines.join("\n")
    end

    def schema_context
      return nil unless defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?

      conn = ActiveRecord::Base.connection
      tables = conn.tables.sort
      return nil if tables.empty?

      lines = ["## Database Schema"]
      tables.each do |table|
        next if table == 'schema_migrations' || table == 'ar_internal_metadata'

        cols = conn.columns(table).map { |c| "#{c.name}:#{c.type}" }
        lines << "- #{table} (#{cols.join(', ')})"
      end
      lines.join("\n")
    rescue => e
      ConsoleAgent.logger.debug("ConsoleAgent: schema introspection failed: #{e.message}")
      nil
    end

    def models_context
      return nil unless defined?(ActiveRecord::Base)

      eager_load_app!
      base_class = defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base
      models = ObjectSpace.each_object(Class).select { |c|
        c < base_class && !c.abstract_class? && c.name && !c.name.start_with?('HABTM_')
      }.sort_by(&:name)

      return nil if models.empty?

      lines = ["## Models"]
      models.each do |model|
        parts = [model.name]

        assocs = model.reflect_on_all_associations.map { |a| "#{a.macro} :#{a.name}" }
        parts << "  associations: #{assocs.join(', ')}" unless assocs.empty?

        scopes = model.methods.grep(/^_scope_/).map { |m| m.to_s.sub('_scope_', '') } rescue []
        if scopes.empty?
          # Alternative: check singleton methods that return ActiveRecord::Relation
          scope_names = (model.singleton_methods - base_class.singleton_methods).select { |m|
            m != :all && !m.to_s.start_with?('_') && !m.to_s.start_with?('find')
          }.first(10)
          # We won't list these to avoid noise — scopes are hard to detect reliably
        end

        validations = model.validators.map { |v|
          attrs = v.attributes.join(', ')
          "#{v.class.name.demodulize.underscore.sub('_validator', '')} on #{attrs}"
        }.uniq.first(5) rescue []
        parts << "  validations: #{validations.join('; ')}" unless validations.empty?

        lines << "- #{parts.join("\n")}"
      end
      lines.join("\n")
    rescue => e
      ConsoleAgent.logger.debug("ConsoleAgent: model introspection failed: #{e.message}")
      nil
    end

    def routes_context
      return nil unless defined?(Rails) && Rails.respond_to?(:application)

      routes = Rails.application.routes.routes
      return nil if routes.empty?

      lines = ["## Routes (summary)"]
      count = 0
      routes.each do |route|
        next if route.internal?
        path = route.path.spec.to_s.sub('(.:format)', '')
        verb = route.verb.to_s
        next if verb.empty?
        action = route.defaults[:controller].to_s + '#' + route.defaults[:action].to_s
        lines << "- #{verb} #{path} -> #{action}"
        count += 1
        break if count >= 50
      end
      lines << "- ... (#{routes.size - count} more routes)" if routes.size > count

      lines.join("\n")
    rescue => e
      ConsoleAgent.logger.debug("ConsoleAgent: route introspection failed: #{e.message}")
      nil
    end

    def memory_context
      return nil unless @config.memories_enabled

      require 'console_agent/tools/memory_tools'
      summaries = Tools::MemoryTools.new.memory_summaries
      return nil if summaries.nil? || summaries.empty?

      lines = ["## Memories"]
      lines.concat(summaries)
      lines << ""
      lines << "Call recall_memories to get details before answering. Do NOT guess from the name alone."
      lines.join("\n")
    rescue => e
      ConsoleAgent.logger.debug("ConsoleAgent: memory context failed: #{e.message}")
      nil
    end

    def eager_load_app!
      return unless defined?(Rails) && Rails.respond_to?(:application)

      if Rails.application.respond_to?(:eager_load!)
        Rails.application.eager_load!
      end
    rescue => e
      ConsoleAgent.logger.debug("ConsoleAgent: eager_load failed: #{e.message}")
    end
  end
end
