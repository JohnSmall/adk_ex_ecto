defmodule ADKExEcto.Schemas.UserState do
  @moduledoc """
  Ecto schema for the `adk_user_states` table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "adk_user_states" do
    field :app_name, :string, primary_key: true
    field :user_id, :string, primary_key: true
    field :state, :map, default: %{}

    timestamps(type: :utc_datetime_usec, inserted_at: false)
  end

  @doc false
  def changeset(user_state, attrs) do
    user_state
    |> cast(attrs, [:app_name, :user_id, :state])
    |> validate_required([:app_name, :user_id])
  end
end
