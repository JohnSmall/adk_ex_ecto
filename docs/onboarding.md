# Onboarding Guide: ADK Ex Ecto

## For New AI Agents / Developers

This document provides everything needed to understand, maintain, and extend the `adk_ex_ecto` package.

---

## 1. What Is This Project?

`adk_ex_ecto` is a companion package to the [Elixir ADK](https://github.com/JohnSmall/adk_ex) (`adk_ex`). It provides **database-backed session persistence** by implementing the `ADK.Session.Service` behaviour using Ecto.

The core ADK uses in-memory storage (GenServer + ETS). This package enables persistent storage that survives process restarts, using any Ecto-compatible database (SQLite3 for dev/test, PostgreSQL for production).

### Relationship to Parent Package

```
adk_ex (core)                          adk_ex_ecto (this package)
├── ADK.Session.Service  ←behaviour──  ADKExEcto.SessionService
├── ADK.Session.InMemory               (replaces this for DB persistence)
├── ADK.Session.State    ←uses──────   (state prefix routing utilities)
├── ADK.Event            ←uses──────   (event struct)
├── ADK.Types.*          ←uses──────   (Content, Part, FunctionCall, etc.)
└── ADK.Runner           ←configures   session_module: ADKExEcto.SessionService
```

---

## 2. Project Structure

```
/workspace/adk_ex_ecto/
├── mix.exs                             # Deps: adk_ex, ecto_sql, ecto_sqlite3, postgrex
├── config/
│   ├── config.exs                      # Imports test.exs in test env
│   └── test.exs                        # SQLite3 in-memory config
├── lib/
│   ├── adk_ex_ecto.ex                  # Top-level module
│   └── adk_ex_ecto/
│       ├── session_service.ex          # Core: ADK.Session.Service implementation
│       ├── migration.ex                # Migration helper (up/0, down/0)
│       └── schemas/
│           ├── session.ex              # adk_sessions table
│           ├── event.ex                # adk_events table
│           ├── app_state.ex            # adk_app_states table
│           └── user_state.ex           # adk_user_states table
├── test/
│   ├── test_helper.exs                 # Starts repo, runs migration
│   ├── adk_ex_ecto/
│   │   └── session_service_test.exs    # 21 tests
│   └── support/
│       ├── test_repo.ex                # SQLite3 test repo
│       └── test_migration.ex           # Runs ADKExEcto.Migration.up/0
├── CLAUDE.md                           # AI agent instructions
├── README.md                           # User-facing documentation
└── docs/
    ├── prd.md                          # Product requirements
    ├── architecture.md                 # Technical architecture
    ├── implementation-plan.md          # Implementation tasks (all complete)
    └── onboarding.md                   # This file
```

---

## 3. Key Resources

| Resource | Location |
|----------|----------|
| **This package** | `/workspace/adk_ex_ecto/` |
| **Parent ADK package** | `/workspace/adk_ex/` |
| **Parent CLAUDE.md** | `/workspace/adk_ex/CLAUDE.md` |
| **Go ADK DB sessions** | `/workspace/adk-go/session/database/` |
| **ADK Session.Service behaviour** | `/workspace/adk_ex/lib/adk/session/service.ex` |
| **ADK Session.State utilities** | `/workspace/adk_ex/lib/adk/session/state.ex` |
| **ADK InMemory (reference impl)** | `/workspace/adk_ex/lib/adk/session/in_memory.ex` |

---

## 4. How It Works

### The Behaviour Contract

`ADK.Session.Service` defines 5 callbacks:

| Callback | Signature | Purpose |
|----------|-----------|---------|
| `create/2` | `(server, opts) -> {:ok, Session.t()} \| {:error, term()}` | Create a new session |
| `get/2` | `(server, opts) -> {:ok, Session.t()} \| {:error, :not_found}` | Fetch session with events and merged state |
| `list/2` | `(server, opts) -> {:ok, [Session.t()]}` | List sessions by app_name + user_id |
| `delete/2` | `(server, opts) -> :ok` | Delete session and its events |
| `append_event/3` | `(server, Session.t(), Event.t()) -> :ok \| {:error, term()}` | Persist event and route state deltas |

In `adk_ex_ecto`, the `server` argument is the user's Ecto Repo module (e.g., `MyApp.Repo`).

### State Routing

The ADK uses prefix-based state scoping. When state deltas arrive via events, they're routed to different tables:

```
Event arrives with state_delta:
  %{"app:model" => "gpt-4", "user:theme" => "dark", "counter" => 1, "temp:x" => "y"}

Routing:
  "app:model"    → adk_app_states.state["model"] = "gpt-4"     (shared: all sessions)
  "user:theme"   → adk_user_states.state["theme"] = "dark"     (shared: user's sessions)
  "counter"      → adk_sessions.state["counter"] = 1           (session-local)
  "temp:x"       → discarded (not persisted)
```

On read, `get/2` merges all three sources back together with prefixes restored.

### Serialization

ADK structs (Content, Part, FunctionCall, etc.) don't map directly to database columns. The SessionService serializes them to JSON maps for storage and deserializes on read.

Key serialization details:
- **Blob data**: Base64-encoded for JSON storage
- **Nil fields**: Omitted from serialized maps (not stored as null)
- **Actions**: All 5 fields always serialized (state_delta, artifact_delta, transfer_to_agent, escalate, skip_summarization)
- **Nil actions**: Deserialize to default `%Actions{}`

### Transaction Boundaries

Two operations use `Repo.transaction/1`:
- **create**: Session insert + app/user state upserts (atomic)
- **append_event**: Event insert + session update + state upserts (atomic)

---

## 5. Development Workflow

### Running Tests

```bash
cd /workspace/adk_ex_ecto
mix deps.get                 # First time only
mix test                     # 21 tests
mix credo                    # Static analysis
mix dialyzer                 # Type checking
```

### Test Architecture

Tests use SQLite3 in-memory database. Each test cleans all 4 tables in its `setup` block — no Ecto sandbox is used.

**Why no sandbox?** SQLite3 in-memory with `pool_size: 1` conflicts with Ecto sandbox. The sandbox tries to wrap each test in a transaction, but the single-connection pool causes checkout timeouts when the migration also needs a connection.

### Adding Tests

1. Add test to `test/adk_ex_ecto/session_service_test.exs`
2. Use the existing `create_session/1` and `make_event/1` helpers
3. No need for `async: true` — tests run synchronously (shared in-memory DB)

---

## 6. Common Maintenance Tasks

### Adding a Column to an Existing Table

1. Update the schema in `lib/adk_ex_ecto/schemas/*.ex` — add the new field
2. Update the changeset's `cast` list to include the new field
3. If persisting event data: update `serialize_*` and `deserialize_*` in `session_service.ex`
4. Update `ADKExEcto.Migration` to include the column in `up/0`
5. Note: existing users will need a new migration for the ALTER TABLE

### Adding a New Table

1. Create a new schema in `lib/adk_ex_ecto/schemas/`
2. Add the CREATE TABLE to `ADKExEcto.Migration.up/0` and DROP to `down/0`
3. Add cleanup to test setup block
4. Note: existing users will need a new migration

### Updating Serialization

If ADK adds new fields to Content, Part, Event, or Actions:
1. Update `serialize_*` functions in `session_service.ex` to include new fields
2. Update `deserialize_*` functions to read new fields (with safe defaults for old data)
3. Add a round-trip test in the "JSON round-trip" describe block

---

## 7. Critical Gotchas

1. **SQLite in-memory + sandbox**: Don't use Ecto sandbox with pool_size 1. Clean tables in setup instead.
2. **Staleness check disabled**: Runner passes original session to `append_event` without re-fetching. Strict timestamp comparison would break on the second event.
3. **Partial events skipped**: Events with `partial: true` are not persisted (returns `:ok` immediately).
4. **No FK constraints**: Events don't have foreign keys to sessions. Delete order matters (events first, then session).
5. **Composite PKs everywhere**: All schemas use `@primary_key false` with composite primary keys.
6. **Repo.get_by for composites**: Use `Repo.get_by(Schema, field1: val1, field2: val2)` — `Repo.get` doesn't work with composite PKs.
7. **State merge on every read**: `get/2` always queries app_states + user_states + session to build merged state. This is 3 queries per get.
8. **upsert pattern**: App/user state uses get-then-insert-or-update, not `ON CONFLICT` (for adapter compatibility).

---

## 8. Relationship to Go ADK

This package mirrors the Go ADK's `session/database/` package:

| Go ADK | Elixir ADK |
|--------|------------|
| `session/database/service.go` | `lib/adk_ex_ecto/session_service.ex` |
| `session/database/storage_types.go` | `lib/adk_ex_ecto/schemas/*.ex` |
| `session/database/migrate.go` | `lib/adk_ex_ecto/migration.ex` |
| GORM (Go ORM) | Ecto |
| `gorm.Open(sqlite.Open(":memory:"))` | `Ecto.Adapters.SQLite3` |
| `AutoMigrate(&Session{}, ...)` | `ADKExEcto.Migration.up/0` |

Key differences:
- Go uses GORM auto-migration; Elixir uses explicit Ecto migrations
- Go uses a single `DatabaseSessionService` struct with a `db` field; Elixir passes the Repo module directly
- Go uses `gorm.Model` (auto ID, timestamps); Elixir uses explicit composite PKs and timestamps
