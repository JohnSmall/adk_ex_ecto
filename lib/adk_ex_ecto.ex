defmodule ADKExEcto do
  @moduledoc """
  Ecto-backed session persistence for ADK.

  Provides `ADKExEcto.SessionService` which implements the
  `ADK.Session.Service` behaviour using Ecto for database storage.

  ## Setup

  1. Add `{:adk_ex_ecto, "~> 0.1"}` to your deps
  2. Generate migration: `mix adk_ex_ecto.gen.migration`
  3. Run migration: `mix ecto.migrate`
  4. Configure your Runner with `session_module: ADKExEcto.SessionService`
  """
end
