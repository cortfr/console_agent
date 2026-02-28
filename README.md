# ConsoleAgent

Claude Code, embedded in your Rails console.

Ask questions in plain English. The AI explores your schema, models, and source code on its own, then writes and runs the Ruby code for you.

## Install

```ruby
# Gemfile
gem 'console_agent', group: :development
```

```bash
bundle install
rails generate console_agent:install
```

Set your API key in the generated initializer or as an env var (`ANTHROPIC_API_KEY`):

```ruby
# config/initializers/console_agent.rb
ConsoleAgent.configure do |config|
  config.api_key = 'sk-ant-...'
end
```

## Usage

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

The AI calls tools behind the scenes to learn your app — schema, models, associations, source code — so it writes accurate queries without you providing any context.

### Commands

| Command | What it does |
|---------|-------------|
| `ai "query"` | One-shot: ask, review code, confirm |
| `ai! "query"` | Interactive: ask and keep chatting |
| `ai? "query"` | Explain only, never executes |

### Multi-Step Plans

For complex tasks, the AI builds a plan and executes it step by step:

```
ai> get the most recent salesforce token and count events via the API
  Thinking...
  -> describe_table("oauth2_tokens")
     28 columns
  -> read_file("lib/salesforce_api.rb")
     202 lines

  Plan (2 steps):
  1. Find the most recent active Salesforce OAuth2 token
     token = Oauth2Token.where(provider: "salesforce", active: true)
                        .order(updated_at: :desc).first
  2. Query event count via SOQL
     api = SalesforceApi.new(step1)
     api.query("SELECT COUNT(Id) FROM Event")

  Accept plan? [y/N/a(uto)] a
  Step 1/2: Find the most recent active Salesforce OAuth2 token
  ...
=> #<Oauth2Token id: 1, provider: "salesforce", ...>

  Step 2/2: Query event count via SOQL
  ...
=> [{"expr0"=>42}]
```

Each step's return value is available to later steps as `step1`, `step2`, etc.

Plan prompt options:
- **y** — accept, then confirm each step one at a time
- **a** — accept and auto-run all steps (stays in manual mode for future queries)
- **N** — decline; you're asked what to change and the AI revises

### Memories

The AI remembers what it learns about your codebase across sessions:

```
ai> how does sharding work?
  -> read_file("config/initializers/sharding.rb")
  -> save_memory("Sharding architecture")
     Memory saved

  This app uses database-per-shard. User.count returns the current shard only.
```

Next time, it already knows — no re-reading files, fewer tokens.

### Interactive Mode

```
irb> ai!
ConsoleAgent interactive mode. Type 'exit' to leave.
  Auto-execute: OFF (Shift-Tab or /auto to toggle)

ai> show me all tables
  ...
ai> count orders by status
  ...
ai> /auto
  Auto-execute: ON
ai> delete cancelled orders older than 90 days
  ...
ai> exit
```

Toggle `/auto` to skip confirmation prompts. `/debug` shows raw API traffic. `/usage` shows token stats.

## Configuration

All settings live in `config/initializers/console_agent.rb` and can be changed at runtime:

```ruby
ConsoleAgent.configure do |config|
  config.provider = :anthropic       # or :openai
  config.auto_execute = false         # true to skip confirmations
  config.max_tokens = 4096             # max tokens per LLM response
  config.max_tool_rounds = 10         # max tool calls per query
  config.session_logging = true       # log sessions to DB (needs migration)
end
```

For session logging and the admin UI, run `rails generate console_agent:install_migrations` and mount the engine:

```ruby
mount ConsoleAgent::Engine => '/console_agent'
```

## Requirements

- Ruby >= 2.5, Rails >= 5.0, Faraday >= 1.0

## License

MIT
