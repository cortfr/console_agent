module ConsoleAgent
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    before_action :authenticate!

    private

    def authenticate!
      username = ConsoleAgent.configuration.admin_username
      password = ConsoleAgent.configuration.admin_password

      return unless username && password

      authenticate_or_request_with_http_basic('ConsoleAgent Admin') do |u, p|
        ActiveSupport::SecurityUtils.secure_compare(u, username) &
          ActiveSupport::SecurityUtils.secure_compare(p, password)
      end
    end
  end
end
