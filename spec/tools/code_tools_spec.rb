require 'spec_helper'
require 'console_agent/tools/code_tools'

RSpec.describe ConsoleAgent::Tools::CodeTools do
  subject(:tools) { described_class.new }

  describe '#read_file' do
    it 'returns error for nil path' do
      expect(tools.read_file(nil)).to include('required')
    end

    it 'returns error for empty path' do
      expect(tools.read_file('')).to include('required')
    end

    it 'returns not available when Rails.root is nil' do
      # No Rails defined in test env
      expect(tools.read_file('app/models/user.rb')).to include('not available')
    end
  end

  describe '#search_code' do
    it 'returns error for nil query' do
      expect(tools.search_code(nil)).to include('required')
    end

    it 'returns error for empty query' do
      expect(tools.search_code('')).to include('required')
    end
  end

  describe '#list_files' do
    it 'returns not available when Rails.root is nil' do
      expect(tools.list_files('app')).to include('not available')
    end
  end
end
