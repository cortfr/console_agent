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

    private

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
