namespace :console_agent do
  desc "Start the ConsoleAgent Slack bot (Socket Mode)"
  task slack: :environment do
    require 'console_agent/slack_bot'
    ConsoleAgent::SlackBot.new.start
  end
end
