require 'spec_helper'
require 'console_agent/providers/base'

RSpec.describe ConsoleAgent::Providers do
  describe '.build' do
    it 'builds an Anthropic provider for :anthropic' do
      ConsoleAgent.configure { |c| c.provider = :anthropic }
      provider = described_class.build
      expect(provider).to be_a(ConsoleAgent::Providers::Anthropic)
    end

    it 'builds an OpenAI provider for :openai' do
      ConsoleAgent.configure { |c| c.provider = :openai }
      provider = described_class.build
      expect(provider).to be_a(ConsoleAgent::Providers::OpenAI)
    end

    it 'raises for unknown provider' do
      ConsoleAgent.configure { |c| c.provider = :unknown }
      expect { described_class.build }.to raise_error(ConsoleAgent::ConfigurationError)
    end
  end
end
