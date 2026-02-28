ConsoleAgent.configure do |config|
  # LLM provider: :anthropic or :openai
  config.provider = :anthropic

  # API key (or set ANTHROPIC_API_KEY / OPENAI_API_KEY env var)
  # config.api_key = 'sk-...'

  # Model override (defaults: claude-opus-4-6 for Anthropic, gpt-5.3-codex for OpenAI)
  # config.model = 'claude-opus-4-6'

  # Max tokens for LLM response
  config.max_tokens = 4096

  # Temperature (0.0 - 1.0)
  config.temperature = 0.2

  # Auto-execute generated code without confirmation (use with caution!)
  config.auto_execute = false

  # Max tool-use rounds per query (safety cap)
  config.max_tool_rounds = 10

  # HTTP timeout in seconds
  config.timeout = 30

  # Debug mode: prints full API requests/responses and tool calls to stderr
  # config.debug = true

  # Session logging: persist AI sessions to the database
  # Requires running: rails generate console_agent:install_migrations && rails db:migrate
  config.session_logging = true

  # Database connection for ConsoleAgent tables (default: ActiveRecord::Base)
  # Set to a class that responds to .connection if tables live on a different DB
  # config.connection_class = Sharding::CentralizedModel

  # Admin UI credentials (mount ConsoleAgent::Engine => '/console_agent' in routes.rb)
  # When nil, no authentication is required (convenient for development)
  # config.admin_username = 'admin'
  # config.admin_password = 'changeme'
end
