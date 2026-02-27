require 'spec_helper'
require 'console_agent/context_builder'
require 'console_agent/providers/base'
require 'console_agent/executor'
require 'console_agent/repl'

RSpec.describe ConsoleAgent::Repl do
  let(:test_binding) { binding }
  let(:mock_provider) { instance_double('ConsoleAgent::Providers::Base') }
  subject(:repl) { described_class.new(test_binding) }

  before do
    ConsoleAgent.configure do |c|
      c.api_key = 'test-key'
      c.provider = :anthropic
    end

    allow(ConsoleAgent::Providers).to receive(:build).and_return(mock_provider)
    allow(ConsoleAgent::ContextBuilder).to receive(:new)
      .and_return(double(build: 'test context'))
  end

  def chat_result(text, input_tokens: 100, output_tokens: 50)
    ConsoleAgent::Providers::ChatResult.new(
      text: text,
      input_tokens: input_tokens,
      output_tokens: output_tokens
    )
  end

  describe '#one_shot' do
    it 'sends query to provider and displays response' do
      allow(mock_provider).to receive(:chat).and_return(
        chat_result("Here is the code:\n```ruby\n1 + 1\n```")
      )
      allow($stdin).to receive(:gets).and_return("y\n")

      result = repl.one_shot('add numbers')
      expect(result).to eq(2)
    end

    it 'returns nil when provider returns no code' do
      allow(mock_provider).to receive(:chat).and_return(
        chat_result('Just an explanation, no code.')
      )

      result = repl.one_shot('explain something')
      expect(result).to be_nil
    end

    it 'handles provider errors gracefully' do
      allow(mock_provider).to receive(:chat)
        .and_raise(ConsoleAgent::Providers::ProviderError, 'API down')

      expect { repl.one_shot('test') }.not_to raise_error
    end
  end

  describe '#explain' do
    it 'displays response without executing' do
      allow(mock_provider).to receive(:chat).and_return(
        chat_result("Explanation:\n```ruby\nUser.count\n```")
      )

      # explain should never prompt for execution
      expect($stdin).not_to receive(:gets)
      result = repl.explain('what does this do')
      expect(result).to be_nil
    end
  end
end
