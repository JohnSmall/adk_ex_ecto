defmodule ADKExEcto.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/JohnSmall/adk_ex_ecto"

  def project do
    [
      app: :adk_ex_ecto,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
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
      {:adk_ex, "~> 0.2"},
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.17", only: [:dev, :test]},
      {:postgrex, "~> 0.19", optional: true},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Ecto-backed session persistence for the Elixir ADK (adk_ex). " <>
      "Database-backed ADK.Session.Service implementation with support for SQLite3 and PostgreSQL."
  end

  defp package do
    [
      name: "adk_ex_ecto",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "ADK Ex" => "https://hex.pm/packages/adk_ex"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        Core: [
          ADKExEcto,
          ADKExEcto.SessionService,
          ADKExEcto.Migration
        ],
        Schemas: [
          ADKExEcto.Schemas.Session,
          ADKExEcto.Schemas.Event,
          ADKExEcto.Schemas.AppState,
          ADKExEcto.Schemas.UserState
        ]
      ]
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end
end
