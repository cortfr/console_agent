require 'spec_helper'
require 'console_agent/executor'

RSpec.describe ConsoleAgent::Executor do
  let(:test_binding) { binding }
  subject(:executor) { described_class.new(test_binding) }

  describe '#extract_code' do
    it 'extracts a single ruby code block' do
      response = <<~TEXT
        Here is some code:
        ```ruby
        User.count
        ```
        That will count users.
      TEXT

      expect(executor.extract_code(response)).to eq("User.count")
    end

    it 'extracts only the first ruby code block' do
      response = <<~TEXT
        First:
        ```ruby
        User.count
        ```
        Then:
        ```ruby
        Post.count
        ```
      TEXT

      code = executor.extract_code(response)
      expect(code).to eq('User.count')
    end

    it 'returns empty string when no code blocks found' do
      expect(executor.extract_code('No code here')).to eq('')
    end

    it 'ignores non-ruby code blocks' do
      response = <<~TEXT
        ```sql
        SELECT * FROM users;
        ```
        ```ruby
        User.all
        ```
      TEXT

      expect(executor.extract_code(response)).to eq("User.all")
    end
  end

  describe '#execute' do
    it 'evaluates code in the given binding' do
      result = executor.execute('1 + 1')
      expect(result).to eq(2)
    end

    it 'returns nil for empty code' do
      expect(executor.execute('')).to be_nil
      expect(executor.execute(nil)).to be_nil
    end

    it 'rescues syntax errors' do
      expect(executor.execute('def foo(')).to be_nil
    end

    it 'rescues runtime errors' do
      expect(executor.execute('raise "boom"')).to be_nil
    end

    it 'sets last_error on syntax error' do
      executor.execute('def foo(')
      expect(executor.last_error).to include('SyntaxError')
    end

    it 'sets last_error on runtime error' do
      executor.execute('raise "boom"')
      expect(executor.last_error).to include('RuntimeError')
      expect(executor.last_error).to include('boom')
    end

    it 'clears last_error on successful execution' do
      executor.execute('raise "boom"')
      expect(executor.last_error).not_to be_nil
      executor.execute('1 + 1')
      expect(executor.last_error).to be_nil
    end
  end

  describe '#store_output and #recall_output' do
    it 'stores and recalls output by id' do
      id = executor.store_output("some output data")
      expect(executor.recall_output(id)).to eq("some output data")
    end

    it 'assigns incrementing ids' do
      id1 = executor.store_output("first")
      id2 = executor.store_output("second")
      expect(id2).to eq(id1 + 1)
    end

    it 'returns nil for unknown id' do
      expect(executor.recall_output(999)).to be_nil
    end
  end

  describe '#expand_output' do
    it 'stores omitted output when display_result truncates' do
      # Execute something that produces a large result
      result = executor.execute('("x" * 5000)')
      expect(executor.expand_output(1)).to include("x" * 100)
    end

    it 'returns nil when no output was omitted' do
      executor.execute('1 + 1')
      expect(executor.expand_output(1)).to be_nil
    end
  end

  describe '#confirm_and_execute' do
    it 'executes on y' do
      allow($stdin).to receive(:gets).and_return("y\n")
      result = executor.confirm_and_execute('1 + 1')
      expect(result).to eq(2)
    end

    it 'does not execute on n' do
      allow($stdin).to receive(:gets).and_return("n\n")
      result = executor.confirm_and_execute('1 + 1')
      expect(result).to be_nil
    end

    it 'does not execute on empty input' do
      allow($stdin).to receive(:gets).and_return("\n")
      result = executor.confirm_and_execute('1 + 1')
      expect(result).to be_nil
    end

    it 'returns nil for empty code' do
      expect(executor.confirm_and_execute('')).to be_nil
    end
  end
end
