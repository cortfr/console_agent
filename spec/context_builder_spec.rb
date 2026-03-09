require 'spec_helper'
require 'rails_console_ai/context_builder'
require 'rails_console_ai/storage/file_storage'
require 'tmpdir'

RSpec.describe RailsConsoleAI::ContextBuilder do
  let(:tmpdir) { Dir.mktmpdir('rails_console_ai_test') }
  let(:storage) { RailsConsoleAI::Storage::FileStorage.new(tmpdir) }
  subject(:builder) { described_class.new }

  before do
    RailsConsoleAI.configure { |c| c.storage_adapter = storage }
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe 'guide_context' do
    it 'includes guide content when file exists' do
      storage.write(RailsConsoleAI::GUIDE_KEY, "# My App\nThis is a Rails app.")

      result = builder.build
      expect(result).to include('## Application Guide')
      expect(result).to include('This is a Rails app.')
    end

    it 'omits guide section when no file exists' do
      result = builder.build
      expect(result).not_to include('## Application Guide')
    end

    it 'omits guide section when file is empty' do
      storage.write(RailsConsoleAI::GUIDE_KEY, '   ')

      result = builder.build
      expect(result).not_to include('## Application Guide')
    end

    it 'places guide before memories' do
      storage.write(RailsConsoleAI::GUIDE_KEY, 'Guide content here')

      RailsConsoleAI.configure { |c| c.memories_enabled = true }
      require 'rails_console_ai/tools/memory_tools'
      memory_tools = RailsConsoleAI::Tools::MemoryTools.new(storage)
      memory_tools.save_memory(name: 'Test', description: 'A fact', tags: ['test'])

      result = builder.build
      guide_pos = result.index('## Application Guide')
      memory_pos = result.index('## Memories')
      expect(guide_pos).not_to be_nil
      expect(memory_pos).not_to be_nil
      expect(guide_pos).to be < memory_pos
    end

    it 'handles storage errors gracefully' do
      failing_storage = instance_double(RailsConsoleAI::Storage::FileStorage)
      allow(failing_storage).to receive(:read).with(RailsConsoleAI::GUIDE_KEY).and_raise(StandardError, 'disk error')
      allow(failing_storage).to receive(:list).and_return([])
      allow(RailsConsoleAI).to receive(:storage).and_return(failing_storage)

      result = builder.build
      expect(result).not_to include('## Application Guide')
    end
  end
end
