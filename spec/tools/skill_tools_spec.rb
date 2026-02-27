require 'spec_helper'
require 'console_agent/storage/file_storage'
require 'console_agent/tools/skill_tools'
require 'tmpdir'

RSpec.describe ConsoleAgent::Tools::SkillTools do
  let(:tmpdir) { Dir.mktmpdir('console_agent_test') }
  let(:storage) { ConsoleAgent::Storage::FileStorage.new(tmpdir) }
  subject(:tools) { described_class.new(storage) }

  after { FileUtils.rm_rf(tmpdir) }

  let(:sharding_skill) do
    <<~MD
      ---
      name: Sharded queries
      description: How to query across database shards.
      ---

      ## Instructions

      Each shard is a separate database.
      Use Shard.switch to change connections.
    MD
  end

  let(:auth_skill) do
    <<~MD
      ---
      name: Authentication
      description: How auth works in this app. Uses Devise.
      ---

      ## Auth Details

      Uses Devise with custom Warden strategies.
    MD
  end

  describe '#load_skill' do
    it 'returns message when no skills exist' do
      expect(tools.load_skill(name: 'anything')).to eq('No skills available.')
    end

    it 'loads a skill by exact name' do
      storage.write('skills/sharding.md', sharding_skill)
      result = tools.load_skill(name: 'Sharded queries')
      expect(result).to include('Skill: Sharded queries')
      expect(result).to include('Each shard is a separate database')
    end

    it 'loads a skill by filename' do
      storage.write('skills/sharding.md', sharding_skill)
      result = tools.load_skill(name: 'sharding')
      expect(result).to include('Skill: Sharded queries')
    end

    it 'loads a skill by partial name match' do
      storage.write('skills/sharding.md', sharding_skill)
      result = tools.load_skill(name: 'shard')
      expect(result).to include('Skill: Sharded queries')
    end

    it 'returns not found with available skills listed' do
      storage.write('skills/sharding.md', sharding_skill)
      storage.write('skills/auth.md', auth_skill)
      result = tools.load_skill(name: 'nonexistent')
      expect(result).to include("not found")
      expect(result).to include('Sharded queries')
      expect(result).to include('Authentication')
    end
  end

  describe '#skill_summaries' do
    it 'returns nil when no skills exist' do
      expect(tools.skill_summaries).to be_nil
    end

    it 'returns summary lines for each skill' do
      storage.write('skills/sharding.md', sharding_skill)
      storage.write('skills/auth.md', auth_skill)

      summaries = tools.skill_summaries
      expect(summaries.length).to eq(2)
      expect(summaries).to include('- Authentication: How auth works in this app. Uses Devise.')
      expect(summaries).to include('- Sharded queries: How to query across database shards.')
    end

    it 'skips files without frontmatter name' do
      storage.write('skills/broken.md', "No frontmatter here")
      expect(tools.skill_summaries).to be_nil
    end
  end
end
