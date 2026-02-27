module ConsoleAgent
  module ConsoleMethods
    def ai_status
      ConsoleAgent.status
    end

    def ai_memories(n = nil)
      require 'yaml'
      content = ConsoleAgent.storage.read('memories.yml')

      if content.nil? || content.strip.empty?
        $stdout.puts "\e[2mNo memories stored yet.\e[0m"
        return nil
      end

      data = YAML.safe_load(content, permitted_classes: [Time, Date]) || {}
      memories = data['memories'] || []

      if memories.empty?
        $stdout.puts "\e[2mNo memories stored yet.\e[0m"
        return nil
      end

      shown = n ? memories.last(n) : memories.last(5)
      total = memories.length

      $stdout.puts "\e[36m[Memories — showing last #{shown.length} of #{total}]\e[0m"
      shown.each do |m|
        $stdout.puts "\e[33m  #{m['name']}\e[0m"
        $stdout.puts "\e[2m  #{m['description']}\e[0m"
        tags = Array(m['tags'])
        $stdout.puts "\e[2m  tags: #{tags.join(', ')}\e[0m" unless tags.empty?
        $stdout.puts
      end

      storage = ConsoleAgent.storage
      path = storage.respond_to?(:root_path) ? File.join(storage.root_path, 'memories.yml') : 'memories.yml'
      $stdout.puts "\e[2mStored in: #{path}\e[0m"
      $stdout.puts "\e[2mUse ai_memories(n) to show last n. Use ai_export to get YAML for your codebase.\e[0m"
      nil
    end

    def ai_skills
      require 'console_agent/tools/skill_tools'
      tools = ConsoleAgent::Tools::SkillTools.new
      summaries = tools.skill_summaries

      if summaries.nil? || summaries.empty?
        $stdout.puts "\e[2mNo skills found. Add .md files to .console_agent/skills/\e[0m"
      else
        $stdout.puts "\e[36m[Skills]\e[0m"
        summaries.each { |s| $stdout.puts s }
        storage = ConsoleAgent.storage
        path = storage.respond_to?(:root_path) ? File.join(storage.root_path, 'skills') : 'skills/'
        $stdout.puts "\e[2mStored in: #{path}\e[0m"
      end
      nil
    end

    def ai_export(n = nil)
      require 'yaml'
      content = ConsoleAgent.storage.read('memories.yml')

      if content.nil? || content.strip.empty?
        $stdout.puts "\e[2mNo memories to export.\e[0m"
        return nil
      end

      data = YAML.safe_load(content, permitted_classes: [Time, Date]) || {}
      memories = data['memories'] || []

      if memories.empty?
        $stdout.puts "\e[2mNo memories to export.\e[0m"
        return nil
      end

      exported = n ? memories.last(n) : memories
      yaml = YAML.dump('memories' => exported)

      $stdout.puts "\e[36m# Add to .console_agent/memories.yml in your codebase and commit:\e[0m"
      $stdout.puts yaml
      $stdout.puts "\e[2m(#{exported.length} memories)\e[0m"
      nil
    end

    def ai(query = nil)
      if query.nil?
        $stderr.puts "\e[33mUsage: ai \"your question here\"\e[0m"
        $stderr.puts "\e[33m  ai  \"query\" - ask + confirm execution\e[0m"
        $stderr.puts "\e[33m  ai! \"query\" - enter interactive mode (or ai! with no args)\e[0m"
        $stderr.puts "\e[33m  ai? \"query\" - explain only, no execution\e[0m"
        $stderr.puts "\e[33m  ai_status   - show current configuration\e[0m"
        $stderr.puts "\e[33m  ai_memories - show recent memories (ai_memories(n) for last n)\e[0m"
        $stderr.puts "\e[33m  ai_skills   - list available skills\e[0m"
        $stderr.puts "\e[33m  ai_export   - dump memory YAML to paste into codebase\e[0m"
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
