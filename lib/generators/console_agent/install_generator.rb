require 'rails/generators'

module ConsoleAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      desc 'Creates a ConsoleAgent initializer in config/initializers/'

      def copy_initializer
        template 'initializer.rb', 'config/initializers/console_agent.rb'
      end

      def show_readme
        say ''
        say 'ConsoleAgent installed!', :green
        say ''
        say 'Next steps:'
        say '  1. Set your API key: export ANTHROPIC_API_KEY=sk-...'
        say '  2. Edit config/initializers/console_agent.rb if needed'
        say '  3. Run: rails console'
        say '  4. Try: ai "show me all tables"'
        say ''
      end
    end
  end
end
