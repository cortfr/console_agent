require 'spec_helper'
require 'console_agent/context_builder'
require 'console_agent/providers/base'
require 'console_agent/executor'
require 'console_agent/repl'

RSpec.describe ConsoleAgent::Repl do
  let(:test_binding) { binding }
  let(:mock_provider) { instance_double('ConsoleAgent::Providers::Anthropic') }
  subject(:repl) { described_class.new(test_binding) }

  before do
    ConsoleAgent.configure do |c|
      c.api_key = 'test-key'
      c.provider = :anthropic
      c.context_mode = :full
    end

    allow(ConsoleAgent::Providers).to receive(:build).and_return(mock_provider)
    allow(ConsoleAgent::ContextBuilder).to receive(:new)
      .and_return(double(build: 'test context'))
  end

  def chat_result(text, input_tokens: 100, output_tokens: 50)
    ConsoleAgent::Providers::ChatResult.new(
      text: text,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      stop_reason: :end_turn
    )
  end

  describe '#one_shot (full mode)' do
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

      expect($stdin).not_to receive(:gets)
      result = repl.explain('what does this do')
      expect(result).to be_nil
    end
  end

  describe '#one_shot (smart mode with tools)' do
    before do
      ConsoleAgent.configure do |c|
        c.api_key = 'test-key'
        c.provider = :anthropic
        c.context_mode = :smart
      end
    end

    it 'runs tool-use loop when LLM requests tools' do
      # First call: LLM wants to call list_tables
      tool_call_result = ConsoleAgent::Providers::ChatResult.new(
        text: '',
        input_tokens: 50,
        output_tokens: 20,
        tool_calls: [{ id: 'tool_1', name: 'list_tables', arguments: {} }],
        stop_reason: :tool_use
      )

      # Second call: LLM produces final answer
      final_result = ConsoleAgent::Providers::ChatResult.new(
        text: "Here are the tables:\n```ruby\nActiveRecord::Base.connection.tables\n```",
        input_tokens: 80,
        output_tokens: 30,
        tool_calls: [],
        stop_reason: :end_turn
      )

      call_count = 0
      allow(mock_provider).to receive(:chat_with_tools) do
        call_count += 1
        call_count == 1 ? tool_call_result : final_result
      end

      allow(mock_provider).to receive(:format_assistant_message).and_return(
        { role: 'assistant', content: [{ 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'list_tables', 'input' => {} }] }
      )
      allow(mock_provider).to receive(:format_tool_result).and_return(
        { role: 'user', content: [{ 'type' => 'tool_result', 'tool_use_id' => 'tool_1', 'content' => 'users, posts' }] }
      )

      allow($stdin).to receive(:gets).and_return("y\n")

      result = repl.one_shot('show tables')
      expect(call_count).to eq(2)
    end

    it 'makes only one call when no tools needed' do
      final_result = ConsoleAgent::Providers::ChatResult.new(
        text: "Sure:\n```ruby\n1 + 1\n```",
        input_tokens: 50,
        output_tokens: 20,
        tool_calls: [],
        stop_reason: :end_turn
      )

      call_count = 0
      allow(mock_provider).to receive(:chat_with_tools) do
        call_count += 1
        final_result
      end

      allow($stdin).to receive(:gets).and_return("y\n")

      repl.one_shot('add numbers')
      expect(call_count).to eq(1)
    end

    it 'aggregates tokens across tool rounds' do
      tool_result = ConsoleAgent::Providers::ChatResult.new(
        text: '', input_tokens: 100, output_tokens: 20,
        tool_calls: [{ id: 't1', name: 'list_tables', arguments: {} }],
        stop_reason: :tool_use
      )
      final_result = ConsoleAgent::Providers::ChatResult.new(
        text: "Done:\n```ruby\n42\n```", input_tokens: 150, output_tokens: 30,
        tool_calls: [], stop_reason: :end_turn
      )

      call_count = 0
      allow(mock_provider).to receive(:chat_with_tools) do
        call_count += 1
        call_count == 1 ? tool_result : final_result
      end
      allow(mock_provider).to receive(:format_assistant_message).and_return({ role: 'assistant', content: [] })
      allow(mock_provider).to receive(:format_tool_result).and_return({ role: 'user', content: [] })
      allow($stdin).to receive(:gets).and_return("y\n")

      # Capture the token display
      output = capture_stdout { repl.one_shot('test') }
      expect(output).to include('in: 250')
      expect(output).to include('out: 50')
    end
  end
end

def capture_stdout
  old_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old_stdout
end
