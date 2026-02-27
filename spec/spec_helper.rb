require 'webmock/rspec'
require 'console_agent'

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.before(:each) do
    ConsoleAgent.reset_configuration!
  end
end
