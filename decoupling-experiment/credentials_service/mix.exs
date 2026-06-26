defmodule CredentialsService.MixProject do
  use Mix.Project

  # Decoupling experiment (Phase 3 slice).
  # A standalone Phoenix/Ecto service that owns ONLY the Credentials surface,
  # extracted from openfn/lightning to prove the slice compiles and tests pass
  # independently of the LiveView monolith. Other surfaces are documented stubs.
  def project do
    [
      app: :credentials_service,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {CredentialsService.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.19"},
      {:cloak_ecto, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
