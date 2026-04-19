# ADK Ex Ecto Usage Rules

`adk_ex_ecto` provides database-backed session persistence for the Elixir ADK (`adk_ex`). It implements the `ADK.Session.Service` behaviour using Ecto, with support for SQLite3 (dev/test) and PostgreSQL (production).

## Setup

### 1. Add Dependencies

```elixir
def deps do
  [
    {:adk_ex, "~> 0.2"},
    {:adk_ex_ecto, "~> 1.0"},
    {:ecto_sqlite3, "~> 0.17"}   # or {:postgrex, "~> 0.19"} for PostgreSQL
  ]
end
```

### 2. Create the Migration

In a new Ecto migration file, delegate to `ADKExEcto.Migration.up/0`:

```elixir
defmodule MyApp.Repo.Migrations.CreateADKTables do
  use Ecto.Migration

  def change do
    ADKExEcto.Migration.up()
  end
end
```

Run `mix ecto.migrate`. This creates 4 tables: `adk_sessions`, `adk_events`, `adk_app_states`, `adk_user_states`.

### 3. Wire Up the Runner

Pass your Ecto Repo as `session_service` and `ADKExEcto.SessionService` as `session_module`:

```elixir
{:ok, runner} = ADK.Runner.new(
  app_name: "my_app",
  root_agent: agent,
  session_service: MyApp.Repo,
  session_module: ADKExEcto.SessionService
)
```

The Repo module plays the role of the `GenServer.server()` argument in the `ADK.Session.Service` behaviour — no extra process is started.

## State Routing

State keys are routed by prefix (matching `ADK.Session.InMemory`):

| Prefix | Table | Scope |
|--------|-------|-------|
| (none) | `adk_sessions.state` | Session-local |
| `app:` | `adk_app_states.state` | Cross-session for the app |
| `user:` | `adk_user_states.state` | Cross-session for the user |
| `temp:` | (not stored) | Current invocation only — discarded on append |

On read, `get/3` merges app/user state (prefix re-added) with session state into a single flat map.

## Database Schema

Composite primary keys, `utc_datetime_usec` timestamps:

- `adk_sessions` — `(app_name, user_id, id)` + `state` (map)
- `adk_events` — `(id, app_name, user_id, session_id)` + `content`, `actions`, metadata
- `adk_app_states` — `(app_name)` + `state`
- `adk_user_states` — `(app_name, user_id)` + `state`

## Serialization

ADK `Content`, `Part`, `FunctionCall`, `FunctionResponse`, and `Actions` structs are JSON-serialized to/from maps automatically. Binary `Blob` data is Base64-encoded.

## Critical Rules

1. **Pass the Repo as `session_service`, not the `SessionService` module** — e.g. `session_service: MyApp.Repo, session_module: ADKExEcto.SessionService`. The Repo is the "server"; the SessionService module implements the behaviour callbacks against it.
2. **Call `ADKExEcto.Migration.up/0` inside an Ecto migration** — don't call it directly at runtime. It wraps `create table/2` calls that must run under the migrator.
3. **Partial events are not persisted** — events with `partial: true` are skipped on `append_event`, matching `ADK.Session.InMemory` behaviour. Only finalized events are stored.
4. **`temp:` state is discarded** — `temp:`-prefixed keys in a state delta are dropped during `append_event` and never written to any table.
5. **Staleness is not checked** — the Runner may call `append_event` with an older session snapshot without re-fetching; this service does not reject on stale `updated_at`.
6. **Don't use the Ecto sandbox with SQLite3 in-memory + pool_size 1** — connections are serialized and the sandbox deadlocks. Clean tables in a `setup` block instead.
7. **Events are deleted before the session on `delete/3`** — foreign-key-like cleanup is done in application code inside a transaction, since composite keys don't auto-cascade.
8. **`create/5` upserts app/user state** — passing state with `app:`/`user:` prefixes on creation will create-or-update the shared-state rows. Existing shared state for other sessions is preserved.

## Testing Pattern

Use SQLite3 in-memory with manual cleanup in `setup`:

```elixir
# test/test_helper.exs
{:ok, _} = MyApp.TestRepo.start_link()
Ecto.Migrator.up(MyApp.TestRepo, 0, MyApp.TestMigration, log: false)
ExUnit.start()
```

```elixir
# in each test module
setup do
  MyApp.TestRepo.delete_all(ADKExEcto.Schemas.Event)
  MyApp.TestRepo.delete_all(ADKExEcto.Schemas.Session)
  MyApp.TestRepo.delete_all(ADKExEcto.Schemas.AppState)
  MyApp.TestRepo.delete_all(ADKExEcto.Schemas.UserState)
  :ok
end
```
