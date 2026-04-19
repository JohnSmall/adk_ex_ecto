# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-04-19

### Added

- `usage-rules.md` for LLM coding agents (see https://hexdocs.pm/usage_rules)
- Listed `usage-rules.md` in package files and ex_doc extras

## [1.0.0] - 2026-04-16

### Added

- `ADKExEcto.SessionService` implementing `ADK.Session.Service` behaviour via Ecto
- `ADKExEcto.Migration` helper for creating the 4 ADK tables (`up/0`, `down/0`)
- Ecto schemas for sessions, events, app state, and user state
- State routing by prefix: `app:`, `user:`, `temp:`, and unprefixed keys
- JSON serialization/deserialization of ADK Content, Parts, FunctionCall, FunctionResponse, and Actions
- Support for SQLite3 (dev/test) and PostgreSQL (production)
- Event filtering with `num_recent_events` and `after` options
- Transactional session creation and event appending with state upserts
