require 'spec_helper'
require 'rails_console_ai/providers/base'

RSpec.describe RailsConsoleAI::Providers do
  describe '.build' do
    it 'builds an Anthropic provider for :anthropic' do
      RailsConsoleAI.configure { |c| c.provider = :anthropic }
      provider = described_class.build
      expect(provider).to be_a(RailsConsoleAI::Providers::Anthropic)
    end

    it 'builds an OpenAI provider for :openai' do
      RailsConsoleAI.configure { |c| c.provider = :openai }
      provider = described_class.build
      expect(provider).to be_a(RailsConsoleAI::Providers::OpenAI)
    end

    it 'raises for unknown provider' do
      RailsConsoleAI.configure { |c| c.provider = :unknown }
      expect { described_class.build }.to raise_error(RailsConsoleAI::ConfigurationError)
    end
  end
end
