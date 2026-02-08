defmodule ADKExEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :adk_ex_ecto,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:adk_ex, path: "../adk_ex"},
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.17", only: [:dev, :test]},
      {:postgrex, "~> 0.19", optional: true},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end
end
