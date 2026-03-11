require 'spec_helper'
require 'rails_console_ai/skill_loader'
require 'rails_console_ai/storage/file_storage'
require 'tmpdir'

RSpec.describe RailsConsoleAi::SkillLoader do
  let(:tmpdir) { Dir.mktmpdir('rails_console_ai_test') }
  let(:storage) { RailsConsoleAi::Storage::FileStorage.new(tmpdir) }
  subject(:loader) { described_class.new(storage) }

  before do
    RailsConsoleAi.configure { |c| c.storage_adapter = storage }
  end

  after { FileUtils.rm_rf(tmpdir) }

  let(:skill_content) do
    <<~MD
      ---
      name: Approve Changes
      description: Approve or reject change approval records
      tags:
        - change-approval
        - admin
      bypass_guards_for_methods:
        - "ChangeApproval#approve_by!"
        - "ChangeApproval#reject_by!"
      ---

      ## When to use
      Use when user asks to approve or reject a change approval.

      ## Recipe
      1. Find the ChangeApproval
      2. Call approve_by! or reject_by!
    MD
  end

  describe '#load_all_skills' do
    it 'returns empty array when skills directory does not exist' do
      expect(loader.load_all_skills).to eq([])
    end

    it 'loads and parses skill files' do
      storage.write('skills/approve-changes.md', skill_content)

      skills = loader.load_all_skills
      expect(skills.length).to eq(1)
      expect(skills.first['name']).to eq('Approve Changes')
      expect(skills.first['description']).to eq('Approve or reject change approval records')
      expect(skills.first['tags']).to eq(['change-approval', 'admin'])
      expect(skills.first['bypass_guards_for_methods']).to eq([
        'ChangeApproval#approve_by!',
        'ChangeApproval#reject_by!'
      ])
      expect(skills.first['body']).to include('## When to use')
      expect(skills.first['body']).to include('## Recipe')
    end

    it 'skips empty files' do
      storage.write('skills/empty.md', '   ')
      expect(loader.load_all_skills).to eq([])
    end

    it 'skips files with invalid frontmatter' do
      storage.write('skills/bad.md', 'no frontmatter here')
      expect(loader.load_all_skills).to eq([])
    end
  end

  describe '#skill_summaries' do
    it 'returns nil when no skills exist' do
      expect(loader.skill_summaries).to be_nil
    end

    it 'returns formatted summaries' do
      storage.write('skills/approve-changes.md', skill_content)

      summaries = loader.skill_summaries
      expect(summaries.length).to eq(1)
      expect(summaries.first).to include('Approve Changes')
      expect(summaries.first).to include('change-approval')
      expect(summaries.first).to include('Approve or reject change approval records')
    end
  end

  describe '#find_skill' do
    before do
      storage.write('skills/approve-changes.md', skill_content)
    end

    it 'finds a skill by exact name (case-insensitive)' do
      skill = loader.find_skill('approve changes')
      expect(skill).not_to be_nil
      expect(skill['name']).to eq('Approve Changes')
    end

    it 'returns nil for unknown skill name' do
      expect(loader.find_skill('nonexistent')).to be_nil
    end
  end
end
