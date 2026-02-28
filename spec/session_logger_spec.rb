require 'spec_helper'
require 'json'
require 'console_agent/session_logger'

RSpec.describe ConsoleAgent::SessionLogger do
  let(:mock_connection) { double('connection') }
  let(:mock_session) { double('SessionClass') }

  before do
    stub_const('ConsoleAgent::Session', mock_session)
    allow(mock_connection).to receive(:table_exists?).with('console_agent_sessions').and_return(true)
    allow(mock_session).to receive(:connection).and_return(mock_connection)
    allow(mock_session).to receive(:create!)

    # Reset memoized state between tests
    described_class.remove_instance_variable(:@table_exists) if described_class.instance_variable_defined?(:@table_exists)
    described_class.remove_instance_variable(:@table_exists_checked) if described_class.instance_variable_defined?(:@table_exists_checked)
    described_class.remove_instance_variable(:@session_class) if described_class.instance_variable_defined?(:@session_class)
  end

  after do
    described_class.remove_instance_variable(:@table_exists) if described_class.instance_variable_defined?(:@table_exists)
    described_class.remove_instance_variable(:@table_exists_checked) if described_class.instance_variable_defined?(:@table_exists_checked)
  end

  describe '.log' do
    let(:attrs) do
      {
        query: 'show all tables',
        conversation: [{ role: :user, content: 'show all tables' }],
        mode: 'one_shot',
        input_tokens: 100,
        output_tokens: 50,
        executed: true,
        code_executed: 'Table.all',
        code_output: 'some output',
        code_result: '[#<Table>]',
        duration_ms: 1234
      }
    end

    it 'creates a Session record with the given attributes' do
      described_class.log(attrs)

      expect(mock_session).to have_received(:create!).with(
        hash_including(
          query: 'show all tables',
          mode: 'one_shot',
          input_tokens: 100,
          output_tokens: 50,
          executed: true,
          code_executed: 'Table.all'
        )
      )
    end

    it 'returns nil when session_logging is disabled' do
      ConsoleAgent.configure { |c| c.session_logging = false }

      described_class.log(attrs)
      expect(mock_session).not_to have_received(:create!)
    end

    it 'returns nil when table does not exist' do
      described_class.remove_instance_variable(:@table_exists) if described_class.instance_variable_defined?(:@table_exists)
    described_class.remove_instance_variable(:@table_exists_checked) if described_class.instance_variable_defined?(:@table_exists_checked)
      allow(mock_connection).to receive(:table_exists?).with('console_agent_sessions').and_return(false)

      result = described_class.log(attrs)
      expect(result).to be_nil
      expect(mock_session).not_to have_received(:create!)
    end

    it 'rescues errors and logs a warning' do
      allow(mock_session).to receive(:create!).and_raise(StandardError, 'db error')
      logger = double('Logger')
      allow(ConsoleAgent).to receive(:logger).and_return(logger)
      allow(logger).to receive(:warn)

      expect(described_class.log(attrs)).to be_nil
      expect(logger).to have_received(:warn).with(/session logging failed/)
    end

    it 'serializes conversation as JSON' do
      described_class.log(attrs)

      expect(mock_session).to have_received(:create!) do |params|
        parsed = JSON.parse(params[:conversation])
        expect(parsed).to be_an(Array)
        expect(parsed.first['role']).to eq('user')
      end
    end

    it 'uses ENV["USER"] for user_name' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('USER').and_return('devuser')

      described_class.log(attrs)

      expect(mock_session).to have_received(:create!).with(
        hash_including(user_name: 'devuser')
      )
    end

    it 'includes provider and model from configuration' do
      ConsoleAgent.configure do |c|
        c.provider = :openai
        c.model = 'gpt-4'
      end

      described_class.log(attrs)

      expect(mock_session).to have_received(:create!).with(
        hash_including(provider: 'openai', model: 'gpt-4')
      )
    end
  end
end
