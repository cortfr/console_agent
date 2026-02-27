require 'spec_helper'
require 'console_agent/tools/registry'

RSpec.describe ConsoleAgent::Tools::Registry do
  subject(:registry) { described_class.new }

  describe '#definitions' do
    it 'registers all expected tools' do
      names = registry.definitions.map { |d| d[:name] }
      expect(names).to include('list_tables', 'describe_table', 'list_models', 'describe_model',
                               'list_files', 'read_file', 'search_code', 'ask_user',
                               'save_memory', 'delete_memory', 'recall_memories', 'load_skill')
    end
  end

  describe '#to_anthropic_format' do
    it 'returns tools in Anthropic format' do
      tools = registry.to_anthropic_format
      expect(tools).to all(include('name', 'description', 'input_schema'))
    end
  end

  describe '#to_openai_format' do
    it 'returns tools in OpenAI format' do
      tools = registry.to_openai_format
      expect(tools).to all(include('type' => 'function'))
      tools.each do |t|
        expect(t['function']).to include('name', 'description', 'parameters')
      end
    end
  end

  describe '#execute' do
    it 'returns error for unknown tool' do
      result = registry.execute('nonexistent', {})
      expect(result).to include('unknown tool')
    end

    it 'handles string arguments (JSON)' do
      # list_tables doesn't need args, so calling with string '{}' should work
      result = registry.execute('list_tables', '{}')
      # May return "ActiveRecord is not connected." or table list
      expect(result).to be_a(String)
    end
  end
end
