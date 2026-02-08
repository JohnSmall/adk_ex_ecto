# ADK Ex Ecto

Ecto-backed session persistence for the [Elixir ADK](https://github.com/JohnSmall/adk_ex) (`adk_ex`).

Implements `ADK.Session.Service` using Ecto, providing database-backed session storage with support for SQLite3 (dev/test) and PostgreSQL (production).

## Installation

Add `adk_ex_ecto` to your dependencies:

```elixir
def deps do
  [
    {:adk_ex, "~> 0.1"},
    {:adk_ex_ecto, "~> 0.1"},
    {:ecto_sqlite3, "~> 0.17"},   # or {:postgrex, "~> 0.19"} for PostgreSQL
  ]
end
```

## Setup

### 1. Create a migration

Add a migration to your project that creates the 4 ADK tables:

```elixir
defmodule MyApp.Repo.Migrations.CreateADKTables do
  use Ecto.Migration

  def change do
    ADKExEcto.Migration.up()
  end
end
```

### 2. Run the migration

```bash
mix ecto.migrate
```

### 3. Configure your Runner

Pass `session_module: ADKExEcto.SessionService` and your Repo as `session_service` to the Runner:

```elixir
{:ok, runner} = ADK.Runner.new(
  app_name: "my_app",
  root_agent: agent,
  session_service: MyApp.Repo,
  session_module: ADKExEcto.SessionService
)
```

## Database Schema

The migration creates 4 tables matching the Go ADK's database session schema:

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `adk_sessions` | `(app_name, user_id, id)` | Session records with state |
| `adk_events` | `(id, app_name, user_id, session_id)` | Event history with content and actions |
| `adk_app_states` | `(app_name)` | Cross-session app-level state |
| `adk_user_states` | `(app_name, user_id)` | Cross-session user-level state |

### State Routing

State keys are routed by prefix (matching `ADK.Session.InMemory` behaviour):

| Prefix | Storage | Shared? |
|--------|---------|---------|
| (none) | `adk_sessions.state` | Session-local |
| `app:` | `adk_app_states.state` | All users/sessions for app |
| `user:` | `adk_user_states.state` | All sessions for user |
| `temp:` | Not persisted | Current invocation only |

## Modules

| Module | Purpose |
|--------|---------|
| `ADKExEcto.SessionService` | Implements `ADK.Session.Service` via Ecto |
| `ADKExEcto.Migration` | Migration helper (`up/0`, `down/0`) |
| `ADKExEcto.Schemas.Session` | Ecto schema for `adk_sessions` |
| `ADKExEcto.Schemas.Event` | Ecto schema for `adk_events` |
| `ADKExEcto.Schemas.AppState` | Ecto schema for `adk_app_states` |
| `ADKExEcto.Schemas.UserState` | Ecto schema for `adk_user_states` |

## Development

```bash
mix deps.get
mix test          # 21 tests
mix credo         # Static analysis
mix dialyzer      # Type checking
```

## License

MIT
