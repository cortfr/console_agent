require 'rails/generators'
require 'rails/generators/active_record'

module ConsoleAgent
  module Generators
    class InstallMigrationsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)
      desc 'Creates the ConsoleAgent database migration for session logging'

      def copy_migration
        migration_template(
          'create_console_agent_sessions.rb.erb',
          'db/migrate/create_console_agent_sessions.rb'
        )
      end

      def show_readme
        say ''
        say 'Migration created!', :green
        say ''
        say 'Next steps:'
        say '  1. Run: rails db:migrate'
        say '  2. Sessions will be automatically logged when using ai "query"'
        say '  3. Mount the admin UI in config/routes.rb:'
        say '       mount ConsoleAgent::Engine => "/console_agent"'
        say ''
      end
    end
  end
end
