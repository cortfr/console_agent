module RailsConsoleAI
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    before_action :rails_console_ai_authenticate!

    private

    def rails_console_ai_authenticate!
      if (auth = RailsConsoleAI.configuration.authenticate)
        instance_exec(&auth)
      else
        username = RailsConsoleAI.configuration.admin_username
        password = RailsConsoleAI.configuration.admin_password

        unless username && password
          head :unauthorized
          return
        end

        authenticate_or_request_with_http_basic('RailsConsoleAI Admin') do |u, p|
          ActiveSupport::SecurityUtils.secure_compare(u, username) &
            ActiveSupport::SecurityUtils.secure_compare(p, password)
        end
      end
    end
  end
end
