defmodule ADKExEcto.TestMigration do
  @moduledoc false
  use Ecto.Migration

  def change do
    ADKExEcto.Migration.up()
  end
end
