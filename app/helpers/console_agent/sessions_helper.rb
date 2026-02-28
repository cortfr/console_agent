module ConsoleAgent
  module SessionsHelper
    def format_message_content(content)
      text = content.is_a?(String) ? content : content.to_json
      # Split on fenced code blocks (```lang ... ```)
      parts = text.split(/(```\w*\n.*?```)/m)

      parts.map do |part|
        if part =~ /\A```\w*\n(.*?)```\z/m
          code = $1.strip
          content_tag(:pre, h(code))
        else
          content_tag(:span, h(part.strip), style: 'white-space: pre-wrap;') unless part.strip.empty?
        end
      end.compact.join("\n").html_safe
    end
  end
end
