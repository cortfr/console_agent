module ConsoleAgent
  module ConsoleMethods
    def ai(query = nil)
      if query.nil?
        $stderr.puts "\e[33mUsage: ai \"your question here\"\e[0m"
        $stderr.puts "\e[33m  ai  \"query\" - ask + confirm execution\e[0m"
        $stderr.puts "\e[33m  ai! \"query\" - enter interactive mode (or ai! with no args)\e[0m"
        $stderr.puts "\e[33m  ai? \"query\" - explain only, no execution\e[0m"
        return nil
      end

      require 'console_agent/context_builder'
      require 'console_agent/providers/base'
      require 'console_agent/executor'
      require 'console_agent/repl'

      repl = Repl.new(__console_agent_binding)
      repl.one_shot(query.to_s)
    rescue => e
      $stderr.puts "\e[31mConsoleAgent error: #{e.message}\e[0m"
      nil
    end

    def ai!(query = nil)
      require 'console_agent/context_builder'
      require 'console_agent/providers/base'
      require 'console_agent/executor'
      require 'console_agent/repl'

      repl = Repl.new(__console_agent_binding)

      if query
        repl.one_shot(query.to_s)
      else
        repl.interactive
      end
    rescue => e
      $stderr.puts "\e[31mConsoleAgent error: #{e.message}\e[0m"
      nil
    end

    def ai?(query = nil)
      unless query
        $stderr.puts "\e[33mUsage: ai? \"your question here\" - explain without executing\e[0m"
        return nil
      end

      require 'console_agent/context_builder'
      require 'console_agent/providers/base'
      require 'console_agent/executor'
      require 'console_agent/repl'

      repl = Repl.new(__console_agent_binding)
      repl.explain(query.to_s)
    rescue => e
      $stderr.puts "\e[31mConsoleAgent error: #{e.message}\e[0m"
      nil
    end

    private

    def __console_agent_binding
      # Try IRB workspace binding
      if defined?(IRB) && IRB.respond_to?(:CurrentContext)
        ctx = IRB.CurrentContext rescue nil
        if ctx && ctx.respond_to?(:workspace) && ctx.workspace.respond_to?(:binding)
          return ctx.workspace.binding
        end
      end

      # Try Pry binding
      if defined?(Pry) && respond_to?(:pry_instance, true)
        pry_inst = pry_instance rescue nil
        if pry_inst && pry_inst.respond_to?(:current_binding)
          return pry_inst.current_binding
        end
      end

      # Fallback
      TOPLEVEL_BINDING
    end
  end
end
