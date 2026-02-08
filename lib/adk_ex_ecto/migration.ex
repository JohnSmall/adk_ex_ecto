defmodule ADKExEcto.Migration do
  @moduledoc """
  Provides migration helper to create the 4 ADK session tables.

  Use `ADKExEcto.Migration.up/0` in your migration file, or generate
  one with `mix adk_ex_ecto.gen.migration`.
  """

  use Ecto.Migration

  def up do
    create table(:adk_sessions, primary_key: false) do
      add :app_name, :string, null: false, primary_key: true
      add :user_id, :string, null: false, primary_key: true
      add :id, :string, null: false, primary_key: true
      add :state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:adk_events, primary_key: false) do
      add :id, :string, null: false, primary_key: true
      add :app_name, :string, null: false, primary_key: true
      add :user_id, :string, null: false, primary_key: true
      add :session_id, :string, null: false, primary_key: true
      add :invocation_id, :string
      add :author, :string
      add :content, :map
      add :actions, :map
      add :branch, :string
      add :partial, :boolean
      add :turn_complete, :boolean
      add :error_code, :string
      add :error_message, :string
      add :interrupted, :boolean
      add :custom_metadata, :map
      add :usage_metadata, :map
      add :citation_metadata, :map
      add :grounding_metadata, :map
      add :long_running_tool_ids, {:array, :string}, default: []
      add :timestamp, :utc_datetime_usec
    end

    create index(:adk_events, [:app_name, :user_id, :session_id])
    create index(:adk_events, [:invocation_id])

    create table(:adk_app_states, primary_key: false) do
      add :app_name, :string, null: false, primary_key: true
      add :state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, inserted_at: false)
    end

    create table(:adk_user_states, primary_key: false) do
      add :app_name, :string, null: false, primary_key: true
      add :user_id, :string, null: false, primary_key: true
      add :state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, inserted_at: false)
    end
  end

  def down do
    drop_if_exists table(:adk_events)
    drop_if_exists table(:adk_user_states)
    drop_if_exists table(:adk_app_states)
    drop_if_exists table(:adk_sessions)
  end
end
