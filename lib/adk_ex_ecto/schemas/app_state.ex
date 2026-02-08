defmodule ADKExEcto.Schemas.AppState do
  @moduledoc """
  Ecto schema for the `adk_app_states` table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "adk_app_states" do
    field :app_name, :string, primary_key: true
    field :state, :map, default: %{}

    timestamps(type: :utc_datetime_usec, inserted_at: false)
  end

  @doc false
  def changeset(app_state, attrs) do
    app_state
    |> cast(attrs, [:app_name, :state])
    |> validate_required([:app_name])
  end
end
