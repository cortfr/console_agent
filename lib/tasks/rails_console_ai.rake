namespace :rails_console_ai do
  desc "Start the RailsConsoleAI Slack bot (Socket Mode)"
  task slack: :environment do
    require 'rails_console_ai/slack_bot'
    RailsConsoleAI::SlackBot.new.start
  end
end
