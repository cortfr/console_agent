require 'spec_helper'
require 'console_agent/storage/file_storage'
require 'console_agent/tools/memory_tools'
require 'tmpdir'

RSpec.describe ConsoleAgent::Tools::MemoryTools do
  let(:tmpdir) { Dir.mktmpdir('console_agent_test') }
  let(:storage) { ConsoleAgent::Storage::FileStorage.new(tmpdir) }
  subject(:tools) { described_class.new(storage) }

  after { FileUtils.rm_rf(tmpdir) }

  describe '#save_memory' do
    it 'saves a memory to storage' do
      result = tools.save_memory(name: 'Test fact', description: 'A useful fact', tags: ['test'])
      expect(result).to include('Memory saved')

      content = storage.read('memories.yml')
      data = YAML.safe_load(content)
      expect(data['memories'].length).to eq(1)
      expect(data['memories'][0]['name']).to eq('Test fact')
      expect(data['memories'][0]['description']).to eq('A useful fact')
      expect(data['memories'][0]['tags']).to eq(['test'])
      expect(data['memories'][0]['id']).to start_with('mem_')
    end

    it 'appends to existing memories' do
      tools.save_memory(name: 'First', description: 'First fact')
      tools.save_memory(name: 'Second', description: 'Second fact')

      content = storage.read('memories.yml')
      data = YAML.safe_load(content)
      expect(data['memories'].length).to eq(2)
    end

    it 'returns fallback text on storage error' do
      failing_storage = instance_double(ConsoleAgent::Storage::FileStorage)
      allow(failing_storage).to receive(:read).and_return(nil)
      allow(failing_storage).to receive(:write).and_raise(
        ConsoleAgent::Storage::StorageError, 'Read-only filesystem'
      )

      tools_with_bad_storage = described_class.new(failing_storage)
      result = tools_with_bad_storage.save_memory(name: 'Test', description: 'Desc')
      expect(result).to include('FAILED to save')
      expect(result).to include('Test')
      expect(result).to include('Desc')
    end
  end

  describe '#recall_memories' do
    before do
      tools.save_memory(name: 'Sharding', description: 'Uses separate databases', tags: ['database'])
      tools.save_memory(name: 'Auth', description: 'Uses Devise for authentication', tags: ['auth', 'users'])
    end

    it 'returns all memories with no filter' do
      result = tools.recall_memories
      expect(result).to include('Sharding')
      expect(result).to include('Auth')
    end

    it 'filters by query' do
      result = tools.recall_memories(query: 'devise')
      expect(result).to include('Auth')
      expect(result).not_to include('Sharding')
    end

    it 'filters by tag' do
      result = tools.recall_memories(tag: 'database')
      expect(result).to include('Sharding')
      expect(result).not_to include('Auth')
    end

    it 'returns message when no memories exist' do
      empty_tools = described_class.new(ConsoleAgent::Storage::FileStorage.new(Dir.mktmpdir))
      expect(empty_tools.recall_memories).to eq('No memories stored yet.')
    end

    it 'returns message when no matches found' do
      result = tools.recall_memories(query: 'nonexistent')
      expect(result).to eq('No memories matching your search.')
    end
  end

  describe '#memory_summaries' do
    it 'returns nil when no memories exist' do
      expect(tools.memory_summaries).to be_nil
    end

    it 'returns name and tags for each memory' do
      tools.save_memory(name: 'Sharding', description: 'Separate DBs per shard', tags: ['database'])
      tools.save_memory(name: 'Auth', description: 'Uses Devise')

      summaries = tools.memory_summaries
      expect(summaries.length).to eq(2)
      expect(summaries[0]).to eq('- Sharding [database]')
      expect(summaries[1]).to eq('- Auth')
    end
  end
end
