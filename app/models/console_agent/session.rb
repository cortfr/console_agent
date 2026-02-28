module ConsoleAgent
  class Session < ActiveRecord::Base
    self.table_name = 'console_agent_sessions'

    validates :query, presence: true
    validates :conversation, presence: true
    validates :mode, presence: true, inclusion: { in: %w[one_shot interactive explain] }

    scope :recent, -> { order(created_at: :desc) }
    scope :named, ->(name) { where(name: name) }
    scope :search, ->(q) { where("name LIKE ? OR query LIKE ?", "%#{q}%", "%#{q}%") }

    def self.connection
      klass = ConsoleAgent.configuration.connection_class
      if klass
        klass = Object.const_get(klass) if klass.is_a?(String)
        klass.connection
      else
        super
      end
    end
  end
end
