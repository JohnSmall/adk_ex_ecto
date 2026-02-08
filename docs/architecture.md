# Architecture Document: ADK Ex Ecto

## Document Info
- **Project**: ADK Ex Ecto
- **Version**: 0.1.0
- **Date**: 2026-02-08
- **Status**: Complete (21 tests, credo clean, dialyzer clean)

---

## 1. Overview

`adk_ex_ecto` provides an Ecto-backed implementation of `ADK.Session.Service`. Unlike the core `adk_ex` InMemory service (which uses GenServer + ETS), this package delegates all storage to a user-provided Ecto Repo, enabling persistent database-backed sessions.

```
ADK.Runner
    |
    +--> session_module: ADKExEcto.SessionService
    |    session_service: MyApp.Repo
    |
    +--> SessionService.create(Repo, opts)
    +--> SessionService.append_event(Repo, session, event)
    +--> SessionService.get(Repo, opts)
    |
    +--> Ecto Repo
         |
         +--> adk_sessions table
         +--> adk_events table
         +--> adk_app_states table
         +--> adk_user_states table
```

---

## 2. Module Map

```
lib/adk_ex_ecto/
  ../adk_ex_ecto.ex                    # Top-level module with @moduledoc
  session_service.ex                   # ADK.Session.Service implementation (467 lines)
  migration.ex                         # Migration helper: up/0 creates 4 tables, down/0 drops them
  schemas/
    session.ex                         # Ecto schema: adk_sessions (composite PK)
    event.ex                           # Ecto schema: adk_events (composite PK)
    app_state.ex                       # Ecto schema: adk_app_states (single PK)
    user_state.ex                      # Ecto schema: adk_user_states (composite PK)
```

### Test Support

```
test/
  adk_ex_ecto/
    session_service_test.exs           # 21 tests covering all operations
  support/
    test_repo.ex                       # ADKExEcto.TestRepo (SQLite3 adapter)
    test_migration.ex                  # Calls ADKExEcto.Migration.up/0
  test_helper.exs                      # Starts repo, runs migration, starts ExUnit
```

---

## 3. Database Schema

### Tables

#### adk_sessions
| Column | Type | Constraint |
|--------|------|------------|
| app_name | string | PK, NOT NULL |
| user_id | string | PK, NOT NULL |
| id | string | PK, NOT NULL |
| state | map (JSON) | NOT NULL, default `{}` |
| inserted_at | utc_datetime_usec | auto |
| updated_at | utc_datetime_usec | auto |

#### adk_events
| Column | Type | Constraint |
|--------|------|------------|
| id | string | PK, NOT NULL |
| app_name | string | PK, NOT NULL |
| user_id | string | PK, NOT NULL |
| session_id | string | PK, NOT NULL |
| invocation_id | string | indexed |
| author | string | |
| content | map (JSON) | |
| actions | map (JSON) | |
| branch | string | |
| partial | boolean | |
| turn_complete | boolean | |
| error_code | string | |
| error_message | string | |
| interrupted | boolean | |
| custom_metadata | map (JSON) | |
| usage_metadata | map (JSON) | |
| citation_metadata | map (JSON) | |
| grounding_metadata | map (JSON) | |
| long_running_tool_ids | array of strings | default `[]` |
| timestamp | utc_datetime_usec | |

**Indexes**: `(app_name, user_id, session_id)`, `(invocation_id)`

#### adk_app_states
| Column | Type | Constraint |
|--------|------|------------|
| app_name | string | PK, NOT NULL |
| state | map (JSON) | NOT NULL, default `{}` |
| updated_at | utc_datetime_usec | auto (no inserted_at) |

#### adk_user_states
| Column | Type | Constraint |
|--------|------|------------|
| app_name | string | PK, NOT NULL |
| user_id | string | PK, NOT NULL |
| state | map (JSON) | NOT NULL, default `{}` |
| updated_at | utc_datetime_usec | auto (no inserted_at) |

---

## 4. SessionService Implementation

### Repo as Server

The `ADK.Session.Service` behaviour defines the first argument as `GenServer.server()`. In this implementation, the Repo module is passed as that argument. All callbacks receive the Repo and use it directly for database operations.

### Operation Details

#### create/2

```
Transaction:
  1. Extract state deltas by prefix (app:/user:/session)
  2. Upsert app_states row (merge delta into existing state)
  3. Upsert user_states row (merge delta into existing state)
  4. Insert session row with session-local state
  5. Build merged state (app + user + session) for return
```

#### get/2

```
1. Fetch session by (app_name, user_id, id)
2. Load events with optional filters:
   - after: DateTime filter (events after timestamp)
   - num_recent_events: limit to N most recent (subquery DESC + re-order ASC)
3. Build merged state from app_states + user_states + session.state
4. Deserialize event content/actions from JSON to ADK structs
```

#### append_event/3

```
If event.partial → skip (return :ok)

Transaction:
  1. Fetch current session row
  2. Extract state_delta prefixes from event.actions
  3. Upsert app_states with app: deltas
  4. Upsert user_states with user: deltas
  5. Merge session-local deltas into session.state
  6. Update session.updated_at
  7. Trim temp: keys from stored delta
  8. Serialize event content/actions to JSON
  9. Insert event row
```

### State Routing

Uses `ADK.Session.State.extract_deltas/1` from the parent `adk_ex` package to split state maps by prefix. The same `merge_states/3` function reassembles them on read.

```
State key "app:model"   → strip prefix → store in adk_app_states.state["model"]
State key "user:pref"   → strip prefix → store in adk_user_states.state["pref"]
State key "temp:scratch" → discard (not persisted)
State key "counter"     → store in adk_sessions.state["counter"]
```

On read, `build_merged_state/4` fetches all three sources and merges with prefixes restored.

---

## 5. Serialization

ADK structs are stored as JSON maps in the database. The SessionService handles serialization and deserialization.

### Content → JSON

```elixir
%Content{role: "model", parts: [%Part{text: "hello"}]}
→ %{"role" => "model", "parts" => [%{"text" => "hello"}]}
```

### Part Fields

| Field | Serialization |
|-------|---------------|
| text | Direct string |
| thought | Boolean |
| function_call | `%{"name" => ..., "id" => ..., "args" => ...}` |
| function_response | `%{"name" => ..., "id" => ..., "response" => ...}` |
| inline_data (Blob) | `%{"data" => Base64.encode64(data), "mime_type" => ...}` |

### Actions → JSON

```elixir
%Actions{state_delta: %{"key" => "val"}, escalate: false, ...}
→ %{"state_delta" => ..., "artifact_delta" => ..., "transfer_to_agent" => nil,
    "escalate" => false, "skip_summarization" => false}
```

---

## 6. Staleness Detection

The SessionService includes a `check_staleness/2` function that is currently a no-op. This is intentional:

The ADK Runner passes the original session struct to `append_event` for each event in a turn, without re-fetching between appends. Strict `updated_at` comparison would fail on the second event since the first append updates the timestamp.

Applications needing strict staleness detection can compare `session.last_update_time` before calling `append_event` at the application level.

---

## 7. Transaction Safety

Both `create/2` and `append_event/3` use `Repo.transaction/1` to ensure atomicity:

- **create**: Session insert + app/user state upserts are atomic
- **append_event**: Event insert + session state update + app/user state upserts are atomic

If any step fails, the entire transaction rolls back.

---

## 8. Differences from InMemory

| Aspect | InMemory | Ecto |
|--------|----------|------|
| Storage | GenServer + 3 ETS tables | Ecto Repo + 4 DB tables |
| Lifecycle | Requires `start_link`, supervised process | Stateless module, uses caller's Repo |
| Concurrency | ETS concurrent reads, GenServer serialized writes | Database-level concurrency |
| Persistence | Process lifetime only | Survives restarts |
| State merge | ETS lookups in merge | SQL queries in merge |
| Partial events | Forwarded but not stored | Skipped entirely |

---

## 9. Testing Strategy

### Setup

Tests use SQLite3 in-memory database (`database: ":memory:"`). No Ecto sandbox — tables are cleaned in each test's `setup` block via `Repo.delete_all`.

Why no sandbox: SQLite3 in-memory with `pool_size: 1` and Ecto sandbox causes connection checkout errors during migration. Direct table cleanup is simpler and more reliable.

### Test Coverage (21 tests)

| Area | Tests | What's Covered |
|------|-------|----------------|
| create | 3 | Basic creation, state prefix routing, explicit session_id |
| get | 4 | Merged state, not_found, num_recent_events limit, chronological order |
| list | 2 | By app+user, different user isolation |
| delete | 1 | Removes session + events |
| append_event | 5 | Persist, state prefix routing, temp discard, updated_at, partial skip |
| app_state sharing | 1 | Visible across sessions |
| user_state sharing | 1 | Visible across user's sessions |
| empty state | 1 | Empty maps serialize correctly |
| JSON round-trip | 1 | Content/FunctionCall survive serialization |
| end-to-end | 1 | Full create → append → get cycle |
| migration | 1 | All 4 tables exist |
