require 'yaml'

module RailsConsoleAi
  class SkillLoader
    SKILLS_DIR = 'skills'

    def initialize(storage = nil)
      @storage = storage || RailsConsoleAi.storage
    end

    def load_all_skills
      keys = @storage.list("#{SKILLS_DIR}/*.md")
      keys.filter_map { |key| load_skill(key) }
    rescue => e
      RailsConsoleAi.logger.warn("RailsConsoleAi: failed to load skills: #{e.message}")
      []
    end

    def skill_summaries
      skills = load_all_skills
      return nil if skills.empty?

      skills.map { |s|
        tags = Array(s['tags'])
        tag_str = tags.empty? ? '' : " [#{tags.join(', ')}]"
        "- **#{s['name']}**#{tag_str}: #{s['description']}"
      }
    end

    def find_skill(name)
      skills = load_all_skills
      skills.find { |s| s['name'].to_s.downcase == name.to_s.downcase }
    end

    def save_skill(name:, description:, body:, tags: [], bypass_guards_for_methods: [])
      key = skill_key(name)
      existing = find_skill(name)

      frontmatter = {
        'name' => name,
        'description' => description,
        'tags' => Array(tags)
      }
      bypasses = Array(bypass_guards_for_methods)
      frontmatter['bypass_guards_for_methods'] = bypasses unless bypasses.empty?

      content = "---\n#{YAML.dump(frontmatter).sub("---\n", '').strip}\n---\n\n#{body}\n"
      @storage.write(key, content)

      path = @storage.respond_to?(:root_path) ? File.join(@storage.root_path, key) : key
      if existing
        "Skill updated: \"#{name}\" (#{path})"
      else
        "Skill created: \"#{name}\" (#{path})"
      end
    rescue Storage::StorageError => e
      "FAILED to save skill (#{e.message})."
    end

    def delete_skill(name:)
      key = skill_key(name)
      unless @storage.exists?(key)
        found = load_all_skills.find { |s| s['name'].to_s.downcase == name.to_s.downcase }
        return "No skill found: \"#{name}\"" unless found
        key = skill_key(found['name'])
      end

      skill = load_skill(key)
      @storage.delete(key)
      "Skill deleted: \"#{skill ? skill['name'] : name}\""
    rescue Storage::StorageError => e
      "FAILED to delete skill (#{e.message})."
    end

    private

    def skill_key(name)
      slug = name.downcase.strip
        .gsub(/[^a-z0-9\s-]/, '')
        .gsub(/[\s]+/, '-')
        .gsub(/-+/, '-')
        .sub(/^-/, '').sub(/-$/, '')
      "#{SKILLS_DIR}/#{slug}.md"
    end

    def load_skill(key)
      content = @storage.read(key)
      return nil if content.nil? || content.strip.empty?
      parse_skill(content)
    rescue => e
      RailsConsoleAi.logger.warn("RailsConsoleAi: failed to load skill #{key}: #{e.message}")
      nil
    end

    def parse_skill(content)
      return nil unless content =~ /\A---\s*\n(.*?\n)---\s*\n(.*)/m
      frontmatter = YAML.safe_load($1, permitted_classes: [Time, Date]) || {}
      body = $2.strip
      frontmatter.merge('body' => body)
    end
  end
end
