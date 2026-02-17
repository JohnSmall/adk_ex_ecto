# Implementation Plan: ADK Ex Ecto

## Document Info
- **Project**: ADK Ex Ecto
- **Version**: 0.1.0
- **Date**: 2026-02-08

---

## Overview

`adk_ex_ecto` implements Ecto-backed session persistence for the Elixir ADK. It was built as Phase 5C of the parent `adk_ex` project. This document records the implementation tasks and their completion status.

---

## Implementation Tasks -- COMPLETE

### 1. Project Setup

- [x] **1.1** Create Mix project at `/workspace/elixir_code/adk_ex_ecto/`
  - Configured mix.exs with deps: adk_ex (path), ecto_sql, ecto_sqlite3, postgrex (optional), jason
  - Added dialyxir and credo for dev/test
  - Set up `elixirc_paths` for test support modules
- [x] **1.2** Configure test environment
  - `config/test.exs`: SQLite3 in-memory, pool_size 1
  - `test/support/test_repo.ex`: TestRepo with SQLite3 adapter
  - `test/support/test_migration.ex`: Calls `ADKExEcto.Migration.up/0`
  - `test/test_helper.exs`: Starts repo, runs migration, starts ExUnit

### 2. Database Schema

- [x] **2.1** Create Migration helper (`lib/adk_ex_ecto/migration.ex`)
  - `up/0`: Creates 4 tables (adk_sessions, adk_events, adk_app_states, adk_user_states)
  - `down/0`: Drops all 4 tables
  - Composite primary keys on all tables
  - `utc_datetime_usec` timestamps for microsecond precision
  - Indexes on events: `(app_name, user_id, session_id)`, `(invocation_id)`
- [x] **2.2** Create Ecto schemas
  - `ADKExEcto.Schemas.Session` — `@primary_key false`, composite PK
  - `ADKExEcto.Schemas.Event` — `@primary_key false`, composite PK, all metadata fields
  - `ADKExEcto.Schemas.AppState` — Single PK (app_name), no inserted_at
  - `ADKExEcto.Schemas.UserState` — Composite PK (app_name, user_id), no inserted_at

### 3. Session Service

- [x] **3.1** Implement `create/2`
  - Transaction: extract deltas → upsert app/user state → insert session
  - Build merged state for return value
- [x] **3.2** Implement `get/2`
  - Fetch session by composite key
  - Load events with optional `num_recent_events` and `after` filters
  - Merge app/user/session state
  - Deserialize events from JSON to ADK structs
- [x] **3.3** Implement `list/2`
  - Query by app_name + user_id
  - Load events and merge state for each session
- [x] **3.4** Implement `delete/2`
  - Delete events first, then session (no FK constraints)
- [x] **3.5** Implement `append_event/3`
  - Skip partial events
  - Transaction: fetch session → extract deltas → upsert states → update session → insert event
  - Trim temp: keys from stored event delta
  - JSON serialization for content and actions

### 4. Serialization

- [x] **4.1** Content serialization/deserialization
  - Content → JSON map with role and parts array
  - Part → conditional fields (text, thought, function_call, function_response, inline_data)
  - FunctionCall/FunctionResponse → name, id, args/response maps
  - Blob → Base64-encoded data + mime_type
- [x] **4.2** Actions serialization/deserialization
  - All 5 fields: state_delta, artifact_delta, transfer_to_agent, escalate, skip_summarization
  - Nil actions deserialize to default `%Actions{}`

### 5. Testing

- [x] **5.1** Create/get/list/delete tests (10 tests)
- [x] **5.2** append_event tests with state routing (5 tests)
- [x] **5.3** Cross-session state sharing tests (2 tests)
- [x] **5.4** Serialization round-trip tests (2 tests)
- [x] **5.5** End-to-end cycle test (1 test)
- [x] **5.6** Migration verification test (1 test)

### 6. Integration with Parent Package

- [x] **6.1** Runner session dispatch (done in `adk_ex`)
  - Added `session_module` field to Runner (default `ADK.Session.InMemory`)
  - All session calls dispatch via `runner.session_module.*`

---

## Verification

```bash
cd /workspace/elixir_code/adk_ex_ecto
mix test          # 21 tests, 0 failures
mix credo         # No issues
mix dialyzer      # 0 errors
```

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate package | Keeps Ecto/DB deps out of core adk_ex |
| Repo as server argument | Matches behaviour's `GenServer.server()` param; flexible |
| No Ecto sandbox in tests | SQLite3 in-memory + pool_size 1 conflicts with sandbox |
| Table cleanup in setup | More reliable than sandbox for SQLite3 in-memory |
| Staleness check disabled | Runner passes original session without re-fetching |
| Composite primary keys | Matches Go ADK schema; natural keys for multi-tenant |
| utc_datetime_usec | Microsecond precision for staleness detection capability |
| JSON for content/actions | Ecto :map type maps directly to JSON columns |
| No FK constraints | Simpler cross-database compatibility; manual cascade in delete |

---

## Go ADK Reference Files

| Component | Go Source |
|-----------|----------|
| Database session service | `/workspace/samples/adk-go/session/database/service.go` |
| Storage types | `/workspace/samples/adk-go/session/database/storage_types.go` |
| Migration | `/workspace/samples/adk-go/session/database/migrate.go` |
| Session interface | `/workspace/samples/adk-go/session/service.go` |
