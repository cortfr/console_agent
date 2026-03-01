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

  def stub_no_tools(result)
    allow(mock_provider).to receive(:chat_with_tools) { result }
  end

  describe '#one_shot' do
    it 'sends query to provider and displays response' do
      stub_no_tools(chat_result("Here is the code:\n```ruby\n1 + 1\n```"))
      allow($stdin).to receive(:gets).and_return("y\n")

      result = repl.one_shot('add numbers')
      expect(result).to eq(2)
    end

    it 'returns nil when provider returns no code' do
      stub_no_tools(chat_result('Just an explanation, no code.'))

      result = repl.one_shot('explain something')
      expect(result).to be_nil
    end

    it 'handles provider errors gracefully' do
      allow(mock_provider).to receive(:chat_with_tools)
        .and_raise(ConsoleAgent::Providers::ProviderError, 'API down')

      expect { repl.one_shot('test') }.not_to raise_error
    end
  end

  describe '#explain' do
    it 'displays response without executing' do
      stub_no_tools(chat_result("Explanation:\n```ruby\nUser.count\n```"))

      expect($stdin).not_to receive(:gets)
      result = repl.explain('what does this do')
      expect(result).to be_nil
    end
  end

  describe 'tool use' do
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
  describe 'interrupt and redirect' do
    it 'prompts for redirect when API call is interrupted and continues with redirect input' do
      call_count = 0
      allow(mock_provider).to receive(:chat_with_tools) do
        call_count += 1
        if call_count == 1
          raise Interrupt
        else
          chat_result("Here you go:\n```ruby\n42\n```")
        end
      end

      allow($stdin).to receive(:gets).and_return("Focus on the users table instead\n")
      allow($stdin).to receive(:cooked) if $stdin.respond_to?(:cooked)

      output = capture_stdout do
        allow($stdin).to receive(:gets).and_return("Focus on the users table instead\n", "y\n")
        result = repl.one_shot('show tables')
        expect(result).to eq(42)
      end

      expect(output).to include('Interrupted')
      expect(output).to include('redirect>')
      expect(call_count).to eq(2)
    end

    it 're-raises Interrupt when redirect input is empty (full abort)' do
      allow(mock_provider).to receive(:chat_with_tools).and_raise(Interrupt)
      allow($stdin).to receive(:gets).and_return("\n")

      expect {
        repl.send(:send_query, 'test')
      }.to raise_error(Interrupt)
    end

    it 're-raises Interrupt when redirect input is nil (Ctrl-D)' do
      allow(mock_provider).to receive(:chat_with_tools).and_raise(Interrupt)
      allow($stdin).to receive(:gets).and_return(nil)

      expect {
        repl.send(:send_query, 'test')
      }.to raise_error(Interrupt)
    end

    it 'injects redirect as a user message in the conversation' do
      call_count = 0
      captured_messages = nil
      allow(mock_provider).to receive(:chat_with_tools) do |messages, **_opts|
        call_count += 1
        if call_count == 1
          raise Interrupt
        else
          captured_messages = messages.dup
          chat_result("Done")
        end
      end

      allow($stdin).to receive(:gets).and_return("Try a different approach\n")

      repl.send(:send_query, 'original query')

      expect(captured_messages).to be_an(Array)
      redirect_msg = captured_messages.find { |m| m[:content] == 'Try a different approach' }
      expect(redirect_msg).not_to be_nil
      expect(redirect_msg[:role]).to eq(:user)
    end

    it 'does not interfere with normal non-interrupted flow' do
      stub_no_tools(chat_result("Result:\n```ruby\n1 + 1\n```"))
      allow($stdin).to receive(:gets).and_return("y\n")

      result = repl.one_shot('add numbers')
      expect(result).to eq(2)
    end
  end

  describe 'direct execution with > prefix' do
    it 'executes code directly and adds result to history' do
      allow(Readline).to receive(:respond_to?).with(:parse_and_bind).and_return(false)

      call_count = 0
      allow(Readline).to receive(:readline) do
        call_count += 1
        call_count == 1 ? '> 1 + 1' : nil
      end

      output = capture_stdout { repl.interactive }

      history = repl.instance_variable_get(:@history)
      expect(history.length).to eq(1)
      expect(history.first[:role]).to eq(:user)
      expect(history.first[:content]).to include('User directly executed code')
      expect(history.first[:content]).to include('1 + 1')
      expect(history.first[:content]).to include('Return value: 2')
    end

    it 'does not call the provider' do
      allow(Readline).to receive(:respond_to?).with(:parse_and_bind).and_return(false)

      call_count = 0
      allow(Readline).to receive(:readline) do
        call_count += 1
        call_count == 1 ? '> 1 + 1' : nil
      end

      expect(mock_provider).not_to receive(:chat_with_tools)

      capture_stdout { repl.interactive }
    end

    it 'works without a space after >' do
      allow(Readline).to receive(:respond_to?).with(:parse_and_bind).and_return(false)

      call_count = 0
      allow(Readline).to receive(:readline) do
        call_count += 1
        call_count == 1 ? '>1 + 1' : nil
      end

      expect(mock_provider).not_to receive(:chat_with_tools)

      capture_stdout { repl.interactive }

      history = repl.instance_variable_get(:@history)
      expect(history.first[:content]).to include('Return value: 2')
    end

    it 'does not treat >= as direct execution' do
      allow(Readline).to receive(:respond_to?).with(:parse_and_bind).and_return(false)

      call_count = 0
      allow(Readline).to receive(:readline) do
        call_count += 1
        call_count == 1 ? '>= 5' : nil
      end

      stub_no_tools(chat_result("Here:\n```ruby\n5\n```"))
      allow($stdin).to receive(:gets).and_return("n\n")

      capture_stdout { repl.interactive }

      expect(mock_provider).to have_received(:chat_with_tools)
    end
  end

  describe '#resume' do
    let(:mock_session) do
      double('Session',
        id: 42,
        query: 'find user 123',
        name: 'sf_user_123',
        conversation: [
          { role: 'user', content: 'find user 123' },
          { role: 'assistant', content: 'Looking up user 123...' }
        ].to_json,
        console_output: "ai> find user 123\nLooking up user 123...\n",
        input_tokens: 100,
        output_tokens: 50
      )
    end

    it 'replays previous console output' do
      allow(Readline).to receive(:readline).and_return(nil) # immediate Ctrl-D
      allow(Readline).to receive(:respond_to?).with(:parse_and_bind).and_return(false)

      output = capture_stdout { repl.resume(mock_session) }
      expect(output).to include('Replaying previous session output')
      expect(output).to include('find user 123')
      expect(output).to include('End of previous output')
    end

    it 'restores token counts from session' do
      allow(Readline).to receive(:readline).and_return(nil)
      allow(Readline).to receive(:respond_to?).with(:parse_and_bind).and_return(false)

      output = capture_stdout { repl.resume(mock_session) }
      # Session summary should show restored token counts
      expect(output).to include('in: 100')
      expect(output).to include('out: 50')
    end

    it 'continues interactive loop after replay' do
      # After replay, user types a new query then exits
      allow(Readline).to receive(:respond_to?).with(:parse_and_bind).and_return(false)
      call_count = 0
      allow(Readline).to receive(:readline) do
        call_count += 1
        call_count == 1 ? 'exit' : nil
      end

      output = capture_stdout { repl.resume(mock_session) }
      expect(output).to include('Left ConsoleAgent interactive mode')
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
