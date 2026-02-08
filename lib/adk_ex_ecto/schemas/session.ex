defmodule ADKExEcto.Schemas.Session do
  @moduledoc """
  Ecto schema for the `adk_sessions` table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "adk_sessions" do
    field :app_name, :string, primary_key: true
    field :user_id, :string, primary_key: true
    field :id, :string, primary_key: true
    field :state, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:app_name, :user_id, :id, :state])
    |> validate_required([:app_name, :user_id, :id])
  end
end
