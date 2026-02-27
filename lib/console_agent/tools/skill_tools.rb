require 'yaml'

module ConsoleAgent
  module Tools
    class SkillTools
      SKILLS_PATTERN = 'skills/*.md'

      def initialize(storage = nil)
        @storage = storage || ConsoleAgent.storage
      end

      def load_skill(name:)
        skill_files = @storage.list(SKILLS_PATTERN)
        return "No skills available." if skill_files.empty?

        skill_file = find_skill_file(skill_files, name)
        unless skill_file
          available = available_skill_names(skill_files)
          return "Skill '#{name}' not found. Available: #{available.join(', ')}"
        end

        content = @storage.read(skill_file)
        return "Could not read skill file." if content.nil?

        fm = parse_frontmatter(content)
        body = extract_body(content)
        "## Skill: #{fm['name'] || name}\n\n#{body}"
      end

      def skill_summaries
        skill_files = @storage.list(SKILLS_PATTERN)
        return nil if skill_files.empty?

        summaries = skill_files.filter_map do |file|
          content = @storage.read(file)
          next if content.nil?

          fm = parse_frontmatter(content)
          next unless fm['name']

          "- #{fm['name']}: #{fm['description'] || '(no description)'}"
        end

        summaries.empty? ? nil : summaries
      end

      private

      def find_skill_file(skill_files, name)
        normalized = name.downcase

        # Exact frontmatter name match
        skill_files.detect { |f| frontmatter_name(f)&.downcase == normalized } ||
          # Filename match
          skill_files.detect { |f| File.basename(f, '.md').downcase == normalized.gsub(/\s+/, '-') } ||
          # Partial frontmatter match
          skill_files.detect { |f| frontmatter_name(f)&.downcase&.include?(normalized) }
      end

      def frontmatter_name(file)
        content = @storage.read(file)
        return nil if content.nil?
        parse_frontmatter(content)['name']
      end

      def available_skill_names(skill_files)
        skill_files.filter_map do |file|
          frontmatter_name(file) || File.basename(file, '.md')
        end
      end

      def parse_frontmatter(content)
        return {} unless content.start_with?("---")

        parts = content.split("---", 3)
        return {} unless parts.length >= 3

        YAML.safe_load(parts[1]) || {}
      rescue
        {}
      end

      def extract_body(content)
        return content unless content.start_with?("---")

        parts = content.split("---", 3)
        parts.length >= 3 ? parts[2].strip : content
      end
    end
  end
end
