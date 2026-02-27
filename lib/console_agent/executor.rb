module ConsoleAgent
  class Executor
    CODE_REGEX = /```ruby\s*\n(.*?)```/m

    attr_reader :binding_context

    def initialize(binding_context)
      @binding_context = binding_context
    end

    def extract_code(response)
      blocks = response.scan(CODE_REGEX).flatten
      blocks.join("\n\n")
    end

    def display_response(response)
      code = extract_code(response)
      explanation = response.gsub(CODE_REGEX, '').strip

      $stdout.puts
      $stdout.puts colorize(explanation, :cyan) unless explanation.empty?

      unless code.empty?
        $stdout.puts
        $stdout.puts colorize("# Generated code:", :yellow)
        $stdout.puts highlight_code(code)
        $stdout.puts
      end

      code
    end

    def execute(code)
      return nil if code.nil? || code.strip.empty?

      result = binding_context.eval(code, "(console_agent)", 1)
      $stdout.puts colorize("=> #{result.inspect}", :green)
      result
    rescue SyntaxError => e
      $stderr.puts colorize("SyntaxError: #{e.message}", :red)
      nil
    rescue => e
      $stderr.puts colorize("Error: #{e.class}: #{e.message}", :red)
      e.backtrace.first(3).each { |line| $stderr.puts colorize("  #{line}", :red) }
      nil
    end

    def confirm_and_execute(code)
      return nil if code.nil? || code.strip.empty?

      $stdout.print colorize("Execute? [y/N/edit] ", :yellow)
      answer = $stdin.gets.to_s.strip.downcase

      case answer
      when 'y', 'yes'
        execute(code)
      when 'e', 'edit'
        edited = open_in_editor(code)
        if edited && edited != code
          $stdout.puts colorize("# Edited code:", :yellow)
          $stdout.puts highlight_code(edited)
          $stdout.print colorize("Execute edited code? [y/N] ", :yellow)
          if $stdin.gets.to_s.strip.downcase == 'y'
            execute(edited)
          else
            $stdout.puts colorize("Cancelled.", :yellow)
            nil
          end
        else
          execute(code)
        end
      else
        $stdout.puts colorize("Cancelled.", :yellow)
        nil
      end
    end

    private

    def open_in_editor(code)
      require 'tempfile'
      editor = ENV['EDITOR'] || 'vi'
      tmpfile = Tempfile.new(['console_agent', '.rb'])
      tmpfile.write(code)
      tmpfile.flush

      system("#{editor} #{tmpfile.path}")
      File.read(tmpfile.path)
    rescue => e
      $stderr.puts colorize("Editor error: #{e.message}", :red)
      code
    ensure
      tmpfile.close! if tmpfile
    end

    def highlight_code(code)
      if coderay_available?
        CodeRay.scan(code, :ruby).terminal
      else
        colorize(code, :white)
      end
    end

    def coderay_available?
      return @coderay_available unless @coderay_available.nil?
      @coderay_available = begin
        require 'coderay'
        true
      rescue LoadError
        false
      end
    end

    COLORS = {
      red:    "\e[31m",
      green:  "\e[32m",
      yellow: "\e[33m",
      cyan:   "\e[36m",
      white:  "\e[37m",
      reset:  "\e[0m"
    }.freeze

    def colorize(text, color)
      if $stdout.respond_to?(:tty?) && $stdout.tty?
        "#{COLORS[color]}#{text}#{COLORS[:reset]}"
      else
        text
      end
    end
  end
end
