# Product Requirements Document: ADK Ex Ecto

## Document Info
- **Project**: ADK Ex Ecto — Ecto-backed session persistence for the Elixir ADK
- **Version**: 0.1.0
- **Date**: 2026-02-08
- **Status**: Complete (21 tests, credo clean, dialyzer clean)
- **GitHub**: github.com/JohnSmall/adk_ex_ecto

---

## 1. Executive Summary

`adk_ex_ecto` is a companion package to the [Elixir ADK](https://github.com/JohnSmall/adk_ex) (`adk_ex`) that provides database-backed session persistence via Ecto. It implements the `ADK.Session.Service` behaviour, enabling ADK agents to store sessions, events, and state in a relational database instead of in-memory ETS tables.

The package follows the same pattern as Google's Go ADK `session/database` package and supports SQLite3 (dev/test) and PostgreSQL (production).

---

## 2. Background and Motivation

### 2.1 Why a Separate Package?

The core `adk_ex` package is transport-agnostic and dependency-light — it has no Ecto, database, or HTTP dependencies. Database persistence is an optional feature that brings significant additional dependencies (Ecto, database adapters). Following the `phoenix`/`phoenix_ecto` pattern, this is provided as a separate hex package.

### 2.2 Why Ecto?

- Ecto is the standard database library in the Elixir ecosystem
- Supports multiple database adapters (PostgreSQL, SQLite3, MySQL)
- Provides migrations, changesets, and query DSL
- Matches the Go ADK pattern of using GORM (Go's standard ORM)

### 2.3 Reference Materials

- **Go ADK database sessions**: `/workspace/adk-go/session/database/service.go`
- **Go ADK storage types**: `/workspace/adk-go/session/database/storage_types.go`
- **Go ADK migration**: `/workspace/adk-go/session/database/migrate.go`
- **Parent package docs**: `/workspace/adk_ex/docs/`

---

## 3. Goals and Non-Goals

### 3.1 Goals

1. **Implement `ADK.Session.Service` behaviour** — Full CRUD + append_event via Ecto
2. **Match Go ADK schema** — Same 4-table design (sessions, events, app_states, user_states)
3. **State prefix routing** — Same `app:`/`user:`/`temp:`/session routing as InMemory
4. **Database-agnostic** — Work with any Ecto adapter (SQLite3 for dev/test, PostgreSQL for prod)
5. **Migration helper** — Provide `ADKExEcto.Migration.up/0` for easy table creation
6. **JSON round-trip fidelity** — Content, Actions, Parts serialize/deserialize without data loss

### 3.2 Non-Goals

- Memory service persistence (Go ADK only has DB for sessions)
- Artifact service persistence (Go ADK only has DB for sessions)
- Connection pooling configuration (user's Repo handles this)
- Multi-tenancy or row-level security
- Automatic migration generation mix task (users create their own migration file)

---

## 4. Requirements

### 4.1 Session Service Operations

| Operation | Description |
|-----------|-------------|
| `create/2` | Create session + upsert app/user state (transaction) |
| `get/2` | Fetch session + events + merge app/user/session state |
| `list/2` | List sessions by app_name + user_id |
| `delete/2` | Delete session and its events |
| `append_event/3` | Persist event + route state deltas + update timestamps (transaction) |

### 4.2 State Routing

State keys must be routed by prefix, matching `ADK.Session.InMemory`:

| Prefix | Table | Behaviour |
|--------|-------|-----------|
| (none) | `adk_sessions.state` | Session-local |
| `app:` | `adk_app_states.state` | Shared across all sessions for app |
| `user:` | `adk_user_states.state` | Shared across user's sessions |
| `temp:` | Not stored | Discarded on persist |

### 4.3 Event Persistence

- Events stored with full content (JSON-serialized Content/Parts/Actions)
- Partial events skipped (not persisted)
- Event queries support `num_recent_events` limit and `after` time filter
- Events returned in chronological order

### 4.4 Serialization

ADK structs must survive JSON round-trip through the database:
- `Content` (role + parts)
- `Part` (text, thought, function_call, function_response, inline_data)
- `FunctionCall` (name, id, args)
- `FunctionResponse` (name, id, response)
- `Blob` (data as Base64, mime_type)
- `Actions` (state_delta, artifact_delta, transfer_to_agent, escalate, skip_summarization)

---

## 5. Technical Constraints

- **Elixir**: >= 1.17
- **Dependencies**: adk_ex, ecto_sql ~> 3.11, jason ~> 1.4
- **Optional deps**: ecto_sqlite3 (dev/test), postgrex (prod)
- **No runtime services**: No GenServer, no application supervision tree
- **Repo provided by user**: The Ecto Repo module is passed as the `server` argument to all behaviour callbacks

---

## 6. Success Criteria

1. All 5 `ADK.Session.Service` callbacks implemented and tested
2. State prefix routing matches InMemory behaviour exactly
3. JSON round-trip preserves all ADK struct data
4. 21 tests passing, credo clean, dialyzer clean
5. Works with SQLite3 (tested) and PostgreSQL (adapter-agnostic queries)
