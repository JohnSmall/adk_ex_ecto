# ADK Ex Ecto - Claude CLI Instructions

## Project Overview

Ecto-backed session persistence for the Elixir ADK (`adk_ex`). Separate hex package providing database-backed `ADK.Session.Service` implementation. Supports SQLite3 (dev/test) and PostgreSQL (prod).

**Parent package**: `adk_ex` at `/workspace/adk_ex/` (github.com/JohnSmall/adk_ex)

## Quick Start

```bash
cd /workspace/adk_ex_ecto
mix deps.get
mix test          # 21 tests
mix credo         # Static analysis
mix dialyzer      # Type checking
```

## Module Map

| Module | Purpose | File |
|--------|---------|------|
| `ADKExEcto` | Top-level module | `lib/adk_ex_ecto.ex` |
| `ADKExEcto.SessionService` | Implements `ADK.Session.Service` via Ecto | `lib/adk_ex_ecto/session_service.ex` |
| `ADKExEcto.Migration` | Creates 4 tables (`up/0`, `down/0`) | `lib/adk_ex_ecto/migration.ex` |
| `ADKExEcto.Schemas.Session` | `adk_sessions` table schema | `lib/adk_ex_ecto/schemas/session.ex` |
| `ADKExEcto.Schemas.Event` | `adk_events` table schema | `lib/adk_ex_ecto/schemas/event.ex` |
| `ADKExEcto.Schemas.AppState` | `adk_app_states` table schema | `lib/adk_ex_ecto/schemas/app_state.ex` |
| `ADKExEcto.Schemas.UserState` | `adk_user_states` table schema | `lib/adk_ex_ecto/schemas/user_state.ex` |

## Architecture

### Session Service

`ADKExEcto.SessionService` implements the `ADK.Session.Service` behaviour. The Ecto Repo module is passed as the `server` argument (matching the behaviour's `GenServer.server()` parameter).

Key operations:
- **create**: Transaction — insert session + upsert app/user state
- **get**: Fetch session + events (with `num_recent_events`/`after` filters) + merge app/user/session state
- **list**: Query sessions by app_name + user_id
- **delete**: Delete events then session
- **append_event**: Transaction — extract state deltas by prefix, upsert app/user/session state, insert event

### State Routing

State keys are routed by prefix (matching `ADK.Session.InMemory`):
- `app:key` -> `adk_app_states` table (strip prefix)
- `user:key` -> `adk_user_states` table (strip prefix)
- `temp:key` -> discarded (not persisted)
- `key` (no prefix) -> `adk_sessions.state`

### Serialization

Content, Parts, FunctionCall, FunctionResponse, and Actions are serialized to JSON maps for storage and deserialized back to ADK structs on read. Blob data is Base64-encoded.

## Database Schema

4 tables with composite primary keys, `utc_datetime_usec` timestamps:

- **adk_sessions**: `(app_name, user_id, id)` + state (map) + timestamps
- **adk_events**: `(id, app_name, user_id, session_id)` + content, actions (maps) + metadata fields
- **adk_app_states**: `(app_name)` + state (map) + updated_at
- **adk_user_states**: `(app_name, user_id)` + state (map) + updated_at

## Critical Rules

1. **SQLite in-memory testing**: Don't use Ecto sandbox with pool_size 1. Clean tables in setup instead.
2. **Staleness check**: Disabled by default — Runner passes original session to `append_event` without re-fetching between appends.
3. **Partial events**: Skipped (not persisted) — matching InMemory behaviour.
4. **Temp state**: `temp:` prefixed keys are discarded during `append_event`, not stored in any table.
5. **Migration**: Use `ADKExEcto.Migration.up/0` inside an Ecto migration file. Don't call it directly.
6. **All tests async**: Use `async: true` unless shared state requires otherwise.

## Test Setup

Tests use SQLite3 in-memory database:
- `test/support/test_repo.ex` — `ADKExEcto.TestRepo` (SQLite3 adapter)
- `test/support/test_migration.ex` — Calls `ADKExEcto.Migration.up/0`
- `test/test_helper.exs` — Starts repo, runs migration, starts ExUnit
- Each test cleans tables in setup block (no Ecto sandbox)

## Reference

- **Go ADK database sessions**: `/workspace/adk-go/session/database/service.go`
- **Go ADK storage types**: `/workspace/adk-go/session/database/storage_types.go`
- **Parent ADK package**: `/workspace/adk_ex/` (see `/workspace/adk_ex/CLAUDE.md`)
