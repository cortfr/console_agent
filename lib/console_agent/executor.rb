require 'stringio'

module ConsoleAgent
  # Writes to two IO streams simultaneously
  class TeeIO
    def initialize(primary, secondary)
      @primary = primary
      @secondary = secondary
    end

    def write(str)
      @primary.write(str)
      @secondary.write(str)
    end

    def puts(*args)
      @primary.puts(*args)
      # Capture what puts would output
      args.each { |a| @secondary.write("#{a}\n") }
      @secondary.write("\n") if args.empty?
    end

    def print(*args)
      @primary.print(*args)
      args.each { |a| @secondary.write(a.to_s) }
    end

    def flush
      @primary.flush if @primary.respond_to?(:flush)
    end

    def respond_to_missing?(method, include_private = false)
      @primary.respond_to?(method, include_private) || super
    end

    def method_missing(method, *args, &block)
      @primary.send(method, *args, &block)
    end
  end

  class Executor
    CODE_REGEX = /```ruby\s*\n(.*?)```/m

    attr_reader :binding_context

    def initialize(binding_context)
      @binding_context = binding_context
    end

    def extract_code(response)
      match = response.match(CODE_REGEX)
      match ? match[1].strip : ''
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

      captured_output = StringIO.new
      old_stdout = $stdout
      # Tee output: capture it and also print to the real stdout
      $stdout = TeeIO.new(old_stdout, captured_output)

      result = binding_context.eval(code, "(console_agent)", 1)

      $stdout = old_stdout
      $stdout.puts colorize("=> #{result.inspect}", :green)

      @last_output = captured_output.string
      result
    rescue SyntaxError => e
      $stdout = old_stdout if old_stdout
      $stderr.puts colorize("SyntaxError: #{e.message}", :red)
      @last_output = nil
      nil
    rescue => e
      $stdout = old_stdout if old_stdout
      $stderr.puts colorize("Error: #{e.class}: #{e.message}", :red)
      e.backtrace.first(3).each { |line| $stderr.puts colorize("  #{line}", :red) }
      @last_output = captured_output&.string
      nil
    end

    def last_output
      @last_output
    end

    def last_cancelled?
      @last_cancelled
    end

    def confirm_and_execute(code)
      return nil if code.nil? || code.strip.empty?

      @last_cancelled = false
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
        @last_cancelled = true
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
