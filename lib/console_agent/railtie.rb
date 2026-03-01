require 'console_agent'

module ConsoleAgent
  class Railtie < Rails::Railtie
    console do
      require 'console_agent/console_methods'

      # Inject into IRB if available
      if defined?(IRB::ExtendCommandBundle)
        IRB::ExtendCommandBundle.include(ConsoleAgent::ConsoleMethods)
      end

      # Extend TOPLEVEL_BINDING's receiver as well
      TOPLEVEL_BINDING.eval('self').extend(ConsoleAgent::ConsoleMethods)

      # Welcome message
      if $stdout.respond_to?(:tty?) && $stdout.tty?
        $stdout.puts "\e[36m[ConsoleAgent v#{ConsoleAgent::VERSION}] AI assistant loaded. Try: ai \"show me all tables\"\e[0m"
      end

      # Pre-build context in background
      Thread.new do
        require 'console_agent/context_builder'
        ConsoleAgent::ContextBuilder.new.build
      rescue => e
        ConsoleAgent.logger.debug("ConsoleAgent: background context build failed: #{e.message}")
      end
    end
  end
end
