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

To set up session logging (OPTIONAL), create the table from the console:

```ruby
ConsoleAgent.setup!
# => ConsoleAgent: created console_agent_sessions table.
```

To reset the table (e.g. after upgrading), run `ConsoleAgent.teardown!` then `ConsoleAgent.setup!`.

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
  Auto-execute: OFF (Shift-Tab or /auto to toggle) | > code to run directly | /usage | /name <label>

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

### Direct Code Execution

Prefix any input with `>` to run Ruby code directly — no LLM round-trip. The result is added to the conversation context, so the AI knows what happened:

```
ai> >User.count
=> 8
ai> how many users do I have?
  Thinking...

You have **8 users** in your database, as confirmed by the `User.count` you just ran.
```

Useful for quick checks, setting up variables, or giving the AI concrete data to work with.

### Sessions

Sessions are saved automatically when session logging is enabled. You can name, list, and resume them.

```
ai> /name sf_user_123_calendar
  Session named: sf_user_123_calendar
ai> exit
Session #42 saved.
  Resume with: ai_resume "sf_user_123_calendar"
Left ConsoleAgent interactive mode.
```

List recent sessions:

```
irb> ai_sessions
[Sessions — showing 3]

  #42 sf_user_123_calendar find user 123 with calendar issues
     [interactive] 5m ago 2340 tokens

  #41 count all active users
     [one_shot] 1h ago 850 tokens

  #40 debug_payments explain payment flow
     [interactive] 2h ago 4100 tokens

Use ai_resume(id_or_name) to resume a session.
```

Resume a session by name or ID — previous output is replayed, then you continue where you left off:

```
irb> ai_resume "sf_user_123_calendar"
--- Replaying previous session output ---
ai> find user 123 with calendar issues
  ...previous output...
--- End of previous output ---

ConsoleAgent interactive mode (sf_user_123_calendar). Type 'exit' to leave.
ai> now check their calendar sync status
  ...
```

Name or rename a session after the fact:

```
irb> ai_name 41, "active_user_count"
Session #41 named: active_user_count
```

Filter sessions by search term:

```
irb> ai_sessions 20, search: "salesforce"
```

If you have an existing `console_agent_sessions` table, run `ConsoleAgent.migrate!` to add the `name` column.

## Configuration

All settings live in `config/initializers/console_agent.rb` and can be changed at runtime:

```ruby
ConsoleAgent.configure do |config|
  config.provider = :anthropic       # or :openai
  config.auto_execute = false         # true to skip confirmations
  config.max_tokens = 4096             # max tokens per LLM response
  config.max_tool_rounds = 10         # max tool calls per query
  config.session_logging = true       # log sessions to DB (run ConsoleAgent.setup!)
end
```

For the admin UI, mount the engine:

```ruby
mount ConsoleAgent::Engine => '/console_agent'
```

## Requirements

- Ruby >= 2.5, Rails >= 5.0, Faraday >= 1.0

## License

MIT
