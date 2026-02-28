# ConsoleAgent

An AI-powered assistant for your Rails console. Ask questions in plain English, get executable Ruby code.

It's like Claude Code embedded in your Rails Console.

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

Set your API key in the generated initializer (`config/initializers/console_agent.rb`):

```ruby
ConsoleAgent.configure do |config|
  config.api_key = 'sk-ant-...'
end
```

Open a console and go:

```ruby
rails console
ai "show me all users who signed up this week"
```

You can also set or change your API key at runtime in the console:

```ruby
ConsoleAgent.configure { |c| c.api_key = 'sk-ant-...' }
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

All settings can be changed at runtime in the console:

```ruby
ConsoleAgent.configure { |c| c.api_key = 'sk-ant-...' }
ConsoleAgent.configure { |c| c.debug = true }
ConsoleAgent.configure { |c| c.provider = :openai; c.api_key = 'sk-...' }
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
| `ask_user` | Ask the console user a clarifying question |
| `save_memory` | Persist a learned fact for future sessions |
| `recall_memories` | Search saved memories |
| `load_skill` | Load full instructions for a skill |

The LLM decides which tools to call based on your question. You can see the tool calls happening in real time.

## Memories & Skills

ConsoleAgent can remember what it learns about your codebase across sessions and load reusable skill instructions on demand.

### Memories

When the AI investigates something complex (like how sharding works in your app), it can save what it learned for next time. Memories are stored in `.console_agent/memories.yml` in your Rails app.

```
ai> how many users are on this shard?
  Thinking...
  -> search_code("shard")
     Found 50 matches
  -> read_file("config/initializers/sharding.rb")
     202 lines
  -> save_memory("Sharding architecture")
     Memory saved: "Sharding architecture"

Each shard is a separate database. User.count returns the count for the current shard only.

  User.count

[tokens in: 2,340 | out: 120 | total: 2,460]
```

Next session, the AI already knows:

```
ai> count users on this shard
  Thinking...

  User.count

[tokens in: 580 | out: 45 | total: 625]
```

The memory file is human-editable YAML:

```yaml
# .console_agent/memories.yml
memories:
  - id: mem_1709123456_42
    name: Sharding architecture
    description: "App uses database-per-shard. Each shard is a separate DB. User.count only counts the current shard."
    tags: [database, sharding]
    created_at: "2026-02-27T10:30:00Z"
```

You can commit this file to your repo so the whole team benefits, or gitignore it for personal use.

### Skills

Skills are reusable instruction files that teach the AI how to handle specific tasks. Store them in `.console_agent/skills/` as markdown files with YAML frontmatter:

```markdown
# .console_agent/skills/sharding.md
---
name: Sharded database queries
description: How to query across database shards. Use when user asks about counting records across shards or shard-specific operations.
---

## Instructions

This app uses Apartment with one database per shard.
- `User.count` only counts the current shard
- To count across all shards: `Shard.all.sum { |s| s.switch { User.count } }`
- Current shard: `Apartment::Tenant.current`
```

Only the skill name and description are sent to the AI on every request (~100 tokens per skill). The full instructions are loaded on demand via the `load_skill` tool only when relevant.

### Storage

By default, memories and skills are stored on the filesystem at `Rails.root/.console_agent/`. This works for development and for production environments with a persistent filesystem.

For containers or other environments where the filesystem is ephemeral, you have two options:

**Option A: Commit to your repo.** Create `.console_agent/memories.yml` and `.console_agent/skills/*.md` in your codebase. They'll be baked into your Docker image.

**Option B: Custom storage adapter.** Implement the storage interface and plug it in:

```ruby
ConsoleAgent.configure do |config|
  config.storage_adapter = MyS3Storage.new(bucket: 'my-bucket', prefix: 'console_agent/')
end
```

A storage adapter just needs four methods: `read(key)`, `write(key, content)`, `list(pattern)`, and `exists?(key)`.

To disable memories or skills:

```ruby
ConsoleAgent.configure do |config|
  config.memories_enabled = false
  config.skills_enabled = false
end
```

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

## Local Development

To develop the gem locally against a Rails app, use a path reference in your Gemfile:

```ruby
gem 'console_agent', path: '/path/to/console_agent'
```

Switch back to the published gem when you're done:

```ruby
gem 'console_agent'
```

## Requirements

- Ruby >= 2.5
- Rails >= 5.0
- Faraday >= 1.0

## License

MIT
