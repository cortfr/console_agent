require 'yaml'

module ConsoleAgent
  module Tools
    class MemoryTools
      MEMORIES_KEY = 'memories.yml'

      def initialize(storage = nil)
        @storage = storage || ConsoleAgent.storage
      end

      def save_memory(name:, description:, tags: [])
        memories = load_memories
        memory = {
          'id' => "mem_#{Time.now.to_i}_#{rand(1000)}",
          'name' => name,
          'description' => description,
          'tags' => Array(tags),
          'created_at' => Time.now.utc.iso8601
        }
        memories << memory
        write_memories(memories)
        path = @storage.respond_to?(:root_path) ? File.join(@storage.root_path, MEMORIES_KEY) : MEMORIES_KEY
        "Memory saved: \"#{name}\" (#{path})"
      rescue Storage::StorageError => e
        "FAILED to save (#{e.message}). Add this manually to .console_agent/memories.yml:\n" \
        "- name: #{name}\n  description: #{description}\n  tags: #{Array(tags).inspect}"
      end

      def recall_memories(query: nil, tag: nil)
        memories = load_memories
        return "No memories stored yet." if memories.empty?

        results = memories
        if tag && !tag.empty?
          results = results.select { |m|
            Array(m['tags']).any? { |t| t.downcase.include?(tag.downcase) }
          }
        end
        if query && !query.empty?
          q = query.downcase
          results = results.select { |m|
            m['name'].to_s.downcase.include?(q) ||
            m['description'].to_s.downcase.include?(q) ||
            Array(m['tags']).any? { |t| t.downcase.include?(q) }
          }
        end

        return "No memories matching your search." if results.empty?

        results.map { |m|
          line = "**#{m['name']}** (#{m['id']})\n#{m['description']}"
          line += "\nTags: #{m['tags'].join(', ')}" if m['tags'] && !m['tags'].empty?
          line
        }.join("\n\n")
      end

      def memory_summaries
        memories = load_memories
        return nil if memories.empty?

        memories.map { |m|
          tags = Array(m['tags'])
          tag_str = tags.empty? ? '' : " [#{tags.join(', ')}]"
          "- #{m['name']}#{tag_str}"
        }
      end

      private

      def load_memories
        content = @storage.read(MEMORIES_KEY)
        return [] if content.nil? || content.strip.empty?

        data = YAML.safe_load(content, permitted_classes: [Time, Date]) || {}
        data['memories'] || []
      rescue => e
        ConsoleAgent.logger.warn("ConsoleAgent: failed to load memories: #{e.message}")
        []
      end

      def write_memories(memories)
        content = YAML.dump('memories' => memories)
        @storage.write(MEMORIES_KEY, content)
      end
    end
  end
end
