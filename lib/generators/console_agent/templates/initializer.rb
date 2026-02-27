ConsoleAgent.configure do |config|
  # LLM provider: :anthropic or :openai
  config.provider = :anthropic

  # API key (or set ANTHROPIC_API_KEY / OPENAI_API_KEY env var)
  # config.api_key = 'sk-...'

  # Model override (defaults: claude-sonnet-4-20250514 for Anthropic, gpt-4o for OpenAI)
  # config.model = 'claude-sonnet-4-20250514'

  # Max tokens for LLM response
  config.max_tokens = 4096

  # Temperature (0.0 - 1.0)
  config.temperature = 0.2

  # Auto-execute generated code without confirmation (use with caution!)
  config.auto_execute = false

  # Context mode: :full (schema + models + routes) or :minimal (environment only)
  config.context_mode = :full

  # HTTP timeout in seconds
  config.timeout = 30
end
