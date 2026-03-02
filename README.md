# ConsoleAgent

Claude Code for your Rails Console.

```
irb> ai "find the 5 most recent orders over $100"
  Thinking...
  -> list_tables
     12 tables: users, orders, line_items, products...
  -> describe_table("orders")
     8 columns

  Order.where("total > ?", 100).order(created_at: :desc).limit(5)

Execute? [y/N/edit] y
=> [#<Order id: 4821, ...>, ...]
```

For complex tasks it builds multi-step plans, executing each step sequentially:

```
ai> get the most recent salesforce token and count events via the API
  Plan (2 steps):
  1. Find the most recent active Salesforce OAuth2 token
     token = Oauth2Token.where(provider: "salesforce", active: true)
                        .order(updated_at: :desc).first
  2. Query event count via SOQL
     api = SalesforceApi.new(step1)
     api.query("SELECT COUNT(Id) FROM Event")

  Accept plan? [y/N/a(uto)] a
```

No context needed from you — it figures out your app on its own.

## Install

```ruby
# Gemfile
gem 'console_agent', group: :development
```

```bash
bundle install
rails generate console_agent:install
```

Set your API key in the generated initializer or via env var (`ANTHROPIC_API_KEY`):

```ruby
# config/initializers/console_agent.rb
ConsoleAgent.configure do |config|
  config.api_key = 'sk-ant-...'
end
```

## Commands

| Command | What it does |
|---------|-------------|
| `ai "query"` | Ask, review generated code, confirm execution |
| `ai!` | Enter interactive mode (multi-turn conversation) |
| `ai? "query"` | Explain only, no execution |
| `ai_init` | Generate app guide for better AI context |
| `ai_setup` | Install session logging table |
| `ai_sessions` | List recent sessions |
| `ai_resume` | Resume a session by name or ID |
| `ai_memories` | Show stored memories |
| `ai_status` | Show current configuration |

### Interactive Mode

`ai!` starts a conversation. Slash commands available inside:

| Command | What it does |
|---------|-------------|
| `/auto` | Toggle auto-execute (skip confirmations) |
| `/compact` | Compress history into a summary (saves tokens) |
| `/usage` | Show token stats |
| `/debug` | Toggle raw API output |
| `/name <label>` | Name the session for easy resume |

Prefix input with `>` to run Ruby directly (no LLM round-trip). The result is added to conversation context.

## Features

- **Tool use** — AI introspects your schema, models, files, and code to write accurate queries
- **Multi-step plans** — complex tasks are broken into steps, executed sequentially with `step1`/`step2` references
- **Memories** — AI saves what it learns about your app across sessions
- **App guide** — `ai_init` generates a guide injected into every system prompt
- **Sessions** — name, list, and resume interactive conversations (`ai_setup` to enable)
- **History compaction** — `/compact` summarizes long conversations to reduce cost and latency

## Configuration

```ruby
ConsoleAgent.configure do |config|
  config.provider = :anthropic       # or :openai
  config.auto_execute = false         # true to skip confirmations
  config.session_logging = true       # requires ai_setup
end
```

## Requirements

Ruby >= 2.5, Rails >= 5.0, Faraday >= 1.0

## License

MIT
