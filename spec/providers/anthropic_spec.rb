require 'spec_helper'
require 'console_agent/providers/base'
require 'console_agent/providers/anthropic'

RSpec.describe ConsoleAgent::Providers::Anthropic do
  let(:config) do
    ConsoleAgent::Configuration.new.tap do |c|
      c.provider = :anthropic
      c.api_key = 'test-anthropic-key'
      c.model = 'claude-test'
      c.max_tokens = 1024
      c.temperature = 0.5
    end
  end

  subject(:provider) { described_class.new(config) }

  describe '#chat' do
    let(:messages) { [{ role: :user, content: 'Hello' }] }

    it 'sends a request to the Anthropic API and returns a ChatResult' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(
          headers: {
            'x-api-key' => 'test-anthropic-key',
            'anthropic-version' => '2023-06-01',
            'Content-Type' => 'application/json'
          }
        )
        .to_return(
          status: 200,
          body: {
            content: [{ type: 'text', text: 'Hello back!' }],
            usage: { input_tokens: 10, output_tokens: 5 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = provider.chat(messages, system_prompt: 'Be helpful')
      expect(result.text).to eq('Hello back!')
      expect(result.input_tokens).to eq(10)
      expect(result.output_tokens).to eq(5)
      expect(result.total_tokens).to eq(15)
    end

    it 'includes system prompt in the request body' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with { |req|
          body = JSON.parse(req.body)
          body['system'] == 'Be helpful'
        }
        .to_return(
          status: 200,
          body: { content: [{ type: 'text', text: 'ok' }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      provider.chat(messages, system_prompt: 'Be helpful')
    end

    it 'raises ProviderError on API errors' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 401,
          body: { error: { message: 'Invalid API key' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect { provider.chat(messages) }.to raise_error(
        ConsoleAgent::Providers::ProviderError, /Invalid API key/
      )
    end

    it 'concatenates multiple text blocks' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: {
            content: [
              { type: 'text', text: 'Part 1' },
              { type: 'text', text: 'Part 2' }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = provider.chat(messages)
      expect(result.text).to eq("Part 1\nPart 2")
    end
  end
end
