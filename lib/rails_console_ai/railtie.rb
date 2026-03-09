require 'rails_console_ai'

module RailsConsoleAI
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path('../tasks/rails_console_ai.rake', __dir__)
    end

    console do
      require 'rails_console_ai/console_methods'

      # Inject into IRB if available
      if defined?(IRB::ExtendCommandBundle)
        IRB::ExtendCommandBundle.include(RailsConsoleAI::ConsoleMethods)
      end

      # Extend TOPLEVEL_BINDING's receiver as well
      TOPLEVEL_BINDING.eval('self').extend(RailsConsoleAI::ConsoleMethods)

      # Welcome message
      if $stdout.respond_to?(:tty?) && $stdout.tty?
        $stdout.puts "\e[36m[RailsConsoleAI v#{RailsConsoleAI::VERSION}] AI assistant loaded. Try: ai \"show me all tables\"\e[0m"
      end

      # Pre-build context in background
      Thread.new do
        require 'rails_console_ai/context_builder'
        RailsConsoleAI::ContextBuilder.new.build
      rescue => e
        RailsConsoleAI.logger.debug("RailsConsoleAI: background context build failed: #{e.message}")
      end
    end
  end
end
