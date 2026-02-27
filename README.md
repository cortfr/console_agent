# ConsoleAgent

An AI-powered assistant for your Rails console. Ask questions in plain English, get executable Ruby code.

ConsoleAgent connects your `rails console` to an LLM (Claude or GPT) and gives it tools to introspect your app's database schema, models, and source code. It figures out what it needs on its own, so you don't pay for 50K tokens of context on every query.

## Quick Start

Add to your Gemfile:

```ruby
gem 'console_agent', group: :development
```

Run the install generator:

```bash
bundle install
rails generate console_agent:install
```

Set your API key and open a console:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
rails console
```

Then:

```ruby
ai "show me all users who signed up this week"
```

## Console Commands

| Command | Description |
|---------|-------------|
| `ai "query"` | Ask a question, review generated code, confirm before executing |
| `ai! "query"` | Ask a question and enter interactive mode for follow-ups |
| `ai!` | Enter interactive mode (type `exit` to leave) |
| `ai? "query"` | Explain only — shows code but never executes |
| `ai_status` | Print current configuration summary |

### Example Session

```
irb> ai "find the 5 most recent orders over $100"
  Thinking...
  -> list_tables
     12 tables: users, orders, line_items, products...
  -> describe_table("orders")
     8 columns
  -> describe_model("Order")
     4 associations, 2 validations

You can query recent high-value orders like this:

  Order.where("total > ?", 100).order(created_at: :desc).limit(5)

[tokens in: 1,240 | out: 85 | total: 1,325]
Execute? [y/N/edit] y
=> [#<Order id: 4821, ...>, ...]
```

### Interactive Mode

```
irb> ai!
ConsoleAgent interactive mode. Type 'exit' or 'quit' to leave.
ai> show me all tables
  Thinking...
  -> list_tables
     12 tables: users, orders, line_items, products...
  ...
ai> now count orders by status
  ...
ai> exit
[session totals — in: 3,200 | out: 410 | total: 3,610]
Left ConsoleAgent interactive mode.
```

### Configuration Status

```
irb> ai_status
[ConsoleAgent v0.1.0]
  Provider:       anthropic
  Model:          claude-opus-4-6
  API key:        sk-ant-...a3b4
  Context mode:   smart
  Max tokens:     4096
  Temperature:    0.2
  Timeout:        30s
  Max tool rounds:10
  Auto-execute:   false
  Debug:          false
```

## Configuration

The install generator creates `config/initializers/console_agent.rb`:

```ruby
ConsoleAgent.configure do |config|
  # LLM provider: :anthropic or :openai
  config.provider = :anthropic

  # API key (or set ANTHROPIC_API_KEY / OPENAI_API_KEY env var)
  # config.api_key = 'sk-...'

  # Model override (defaults: claude-opus-4-6 for Anthropic, gpt-5.3-codex for OpenAI)
  # config.model = 'claude-opus-4-6'

  # Context mode:
  #   :smart - (default) LLM uses tools to fetch schema/model/code on demand
  #   :full  - sends all schema, models, and routes every time
  config.context_mode = :smart

  # Max tokens for LLM response
  config.max_tokens = 4096

  # Temperature (0.0 - 1.0)
  config.temperature = 0.2

  # Auto-execute generated code without confirmation
  config.auto_execute = false

  # Max tool-use rounds per query in :smart mode
  config.max_tool_rounds = 10

  # HTTP timeout in seconds
  config.timeout = 30

  # Debug mode: prints full API requests/responses and tool calls
  # config.debug = true
end
```

You can also change settings at runtime in the console:

```ruby
ConsoleAgent.configure { |c| c.debug = true }
ConsoleAgent.configure { |c| c.provider = :openai }
ENV['OPENAI_API_KEY'] = 'sk-...'
```

## Context Modes

### Smart Mode (default)

The LLM gets a minimal system prompt and uses tools to look up what it needs:

- **list_tables** / **describe_table** — database schema on demand
- **list_models** / **describe_model** — ActiveRecord associations, validations
- **list_files** / **read_file** / **search_code** — browse app source code

This keeps token usage low (~1-3K per query) even for large apps with hundreds of tables.

### Full Mode

Sends the entire database schema, all model details, and a route summary in every request. Simple but expensive for large apps (~50K+ tokens). Useful if you want everything available without tool-call round trips.

```ruby
ConsoleAgent.configure { |c| c.context_mode = :full }
```

## Tools Available in Smart Mode

| Tool | Description |
|------|-------------|
| `list_tables` | All database table names |
| `describe_table` | Columns, types, and indexes for one table |
| `list_models` | All model names with association names |
| `describe_model` | Associations, validations, scopes for one model |
| `list_files` | Ruby files in a directory |
| `read_file` | Read a source file (capped at 200 lines) |
| `search_code` | Grep for a pattern across Ruby files |

The LLM decides which tools to call based on your question. You can see the tool calls happening in real time.

## Providers

### Anthropic (default)

Uses the Claude Messages API. Set `ANTHROPIC_API_KEY` or `config.api_key`.

### OpenAI

Uses the Chat Completions API. Set `OPENAI_API_KEY` or `config.api_key`.

```ruby
ConsoleAgent.configure do |config|
  config.provider = :openai
  config.model = 'gpt-5.3-codex'  # optional, this is the default
end
```

## Docker Setup

If your Rails app runs in Docker, mount the gem source as a volume.

In `docker-compose.yml`:

```yaml
volumes:
  - /path/to/console_agent:/console_agent
```

In `Gemfile`:

```ruby
gem 'console_agent', path: '/console_agent', group: :development
```

For Docker builds (where the gem source isn't available yet), add a stub to your Dockerfile before `bundle install`:

```dockerfile
RUN mkdir -p /console_agent/lib/console_agent && \
    echo "module ConsoleAgent; VERSION = '0.1.0'; end" > /console_agent/lib/console_agent/version.rb && \
    echo "require 'console_agent/version'" > /console_agent/lib/console_agent.rb && \
    printf "require_relative 'lib/console_agent/version'\nGem::Specification.new do |s|\n  s.name = 'console_agent'\n  s.version = ConsoleAgent::VERSION\n  s.summary = 'stub'\n  s.authors = ['x']\n  s.files = ['lib/console_agent.rb']\n  s.add_dependency 'rails', '>= 5.0'\n  s.add_dependency 'faraday', '>= 1.0'\nend\n" > /console_agent/console_agent.gemspec
```

The volume mount overwrites the stub at runtime with the real source.

## Requirements

- Ruby >= 2.5
- Rails >= 5.0
- Faraday >= 1.0

## License

MIT
