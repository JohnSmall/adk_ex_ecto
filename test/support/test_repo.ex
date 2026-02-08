defmodule ADKExEcto.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :adk_ex_ecto,
    adapter: Ecto.Adapters.SQLite3
end
