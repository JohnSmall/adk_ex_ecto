defmodule ADKExEcto.Schemas.Event do
  @moduledoc """
  Ecto schema for the `adk_events` table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "adk_events" do
    field :id, :string, primary_key: true
    field :app_name, :string, primary_key: true
    field :user_id, :string, primary_key: true
    field :session_id, :string, primary_key: true
    field :invocation_id, :string
    field :author, :string
    field :content, :map
    field :actions, :map
    field :branch, :string
    field :partial, :boolean
    field :turn_complete, :boolean
    field :error_code, :string
    field :error_message, :string
    field :interrupted, :boolean
    field :custom_metadata, :map
    field :usage_metadata, :map
    field :citation_metadata, :map
    field :grounding_metadata, :map
    field :long_running_tool_ids, {:array, :string}, default: []
    field :timestamp, :utc_datetime_usec
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :app_name,
      :user_id,
      :session_id,
      :invocation_id,
      :author,
      :content,
      :actions,
      :branch,
      :partial,
      :turn_complete,
      :error_code,
      :error_message,
      :interrupted,
      :custom_metadata,
      :usage_metadata,
      :citation_metadata,
      :grounding_metadata,
      :long_running_tool_ids,
      :timestamp
    ])
    |> validate_required([:id, :app_name, :user_id, :session_id])
  end
end
