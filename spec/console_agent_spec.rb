require 'spec_helper'

RSpec.describe ConsoleAgent do
  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(ConsoleAgent.configuration).to be_a(ConsoleAgent::Configuration)
    end

    it 'returns the same instance on repeated calls' do
      expect(ConsoleAgent.configuration).to equal(ConsoleAgent.configuration)
    end
  end

  describe '.configure' do
    it 'yields the configuration object' do
      ConsoleAgent.configure do |config|
        config.provider = :openai
        config.max_tokens = 2048
      end

      expect(ConsoleAgent.configuration.provider).to eq(:openai)
      expect(ConsoleAgent.configuration.max_tokens).to eq(2048)
    end
  end

  describe '.reset_configuration!' do
    it 'creates a fresh configuration' do
      ConsoleAgent.configure { |c| c.provider = :openai }
      ConsoleAgent.reset_configuration!
      expect(ConsoleAgent.configuration.provider).to eq(:anthropic)
    end
  end
end
