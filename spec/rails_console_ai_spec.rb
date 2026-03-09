require 'spec_helper'

RSpec.describe RailsConsoleAI do
  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(RailsConsoleAI.configuration).to be_a(RailsConsoleAI::Configuration)
    end

    it 'returns the same instance on repeated calls' do
      expect(RailsConsoleAI.configuration).to equal(RailsConsoleAI.configuration)
    end
  end

  describe '.configure' do
    it 'yields the configuration object' do
      RailsConsoleAI.configure do |config|
        config.provider = :openai
        config.max_tokens = 2048
      end

      expect(RailsConsoleAI.configuration.provider).to eq(:openai)
      expect(RailsConsoleAI.configuration.max_tokens).to eq(2048)
    end
  end

  describe '.reset_configuration!' do
    it 'creates a fresh configuration' do
      RailsConsoleAI.configure { |c| c.provider = :openai }
      RailsConsoleAI.reset_configuration!
      expect(RailsConsoleAI.configuration.provider).to eq(:anthropic)
    end
  end
end
