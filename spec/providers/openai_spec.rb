require 'spec_helper'
require 'console_agent/providers/base'
require 'console_agent/providers/openai'

RSpec.describe ConsoleAgent::Providers::OpenAI do
  let(:config) do
    ConsoleAgent::Configuration.new.tap do |c|
      c.provider = :openai
      c.api_key = 'test-openai-key'
      c.model = 'gpt-test'
      c.max_tokens = 1024
      c.temperature = 0.5
    end
  end

  subject(:provider) { described_class.new(config) }

  describe '#chat' do
    let(:messages) { [{ role: :user, content: 'Hello' }] }

    it 'sends a request to the OpenAI API and returns a ChatResult' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with(
          headers: {
            'Authorization' => 'Bearer test-openai-key',
            'Content-Type' => 'application/json'
          }
        )
        .to_return(
          status: 200,
          body: {
            choices: [{ message: { content: 'Hello back!' } }],
            usage: { prompt_tokens: 20, completion_tokens: 8, total_tokens: 28 }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = provider.chat(messages, system_prompt: 'Be helpful')
      expect(result.text).to eq('Hello back!')
      expect(result.input_tokens).to eq(20)
      expect(result.output_tokens).to eq(8)
      expect(result.total_tokens).to eq(28)
    end

    it 'prepends system message when system_prompt is given' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .with { |req|
          body = JSON.parse(req.body)
          body['messages'][0]['role'] == 'system' &&
            body['messages'][0]['content'] == 'Be helpful'
        }
        .to_return(
          status: 200,
          body: { choices: [{ message: { content: 'ok' } }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      provider.chat(messages, system_prompt: 'Be helpful')
    end

    it 'raises ProviderError on API errors' do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(
          status: 429,
          body: { error: { message: 'Rate limit exceeded' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect { provider.chat(messages) }.to raise_error(
        ConsoleAgent::Providers::ProviderError, /Rate limit exceeded/
      )
    end
  end
end
