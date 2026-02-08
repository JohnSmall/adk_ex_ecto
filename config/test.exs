import Config

config :adk_ex_ecto, ADKExEcto.TestRepo,
  database: ":memory:",
  pool_size: 1

config :adk_ex_ecto, ecto_repos: [ADKExEcto.TestRepo]
