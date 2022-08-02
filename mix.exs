defmodule Lightning.MixProject do
  use Mix.Project

  def project do
    [
      app: :lightning,
      version: "0.1.9",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        verify: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Docs
      name: "Lightning",
      docs: docs()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Lightning.Application, [:timex]},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # {:engine, path: "../engine"},
      # {:rexbug, ">= 1.0.0", only: :test},
      {:bcrypt_elixir, "~> 2.0"},
      {:bodyguard, "~> 2.2"},
      {:cloak_ecto, "~> 1.2.0"},
      {:credo, "~> 1.6", only: [:test, :dev]},
      {:crontab, "~> 1.1"},
      {:dialyxir, "~> 1.1", only: [:test, :dev], runtime: false},
      {:ecto_enum, "~> 1.4"},
      {:ecto_sql, "~> 3.6"},
      {:engine, github: "OpenFn/engine", tag: "v0.7.2"},
      {:esbuild, "~> 0.3", runtime: Mix.env() == :dev},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:excoveralls, "~> 0.14.4", only: [:test, :dev]},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.18"},
      {:hackney, "~> 1.8"},
      {:httpoison, "~> 1.8"},
      {:jason, "~> 1.2"},
      {:joken, "~> 2.4.1"},
      {:junit_formatter, "~> 3.0", only: [:test]},
      {:mimic, "~> 1.7.2", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:test, :dev], runtime: false},
      {:oban, "~> 2.13"},
      {:petal_components, "~> 0.17"},
      {:phoenix, "~> 1.6.7"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.2"},
      {:phoenix_live_dashboard, "~> 0.6.5"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.17.10"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:scrivener_ecto, "~> 2.7"},
      {:sentry, "~> 8.0"},
      {:sobelow, "~> 0.11.1", only: [:test, :dev]},
      {:sweet_xml, "~> 0.7.1", only: [:test]},
      {:swoosh, "~> 1.3"},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:temp, "~> 0.4"},
      {:timex, "~> 3.7"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": [
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ],
      verify: [
        "coveralls.html",
        "format --check-formatted",
        "dialyzer",
        "credo --all",
        "sobelow"
      ]
    ]
  end

  defp docs() do
    [
      # The main page in the docs
      main: "readme",
      logo: "priv/static/images/square-logo.png",
      extras: [
        "README.md": [title: "Lightning"],
        "DEPLOYMENT.md": [title: "Deployment"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      source_url: "https://github.com/OpenFn/lightning",
      homepage_url: "https://www.openfn.org",
      groups_for_modules: [
        Accounts: [
          Lightning.Accounts,
          Lightning.Accounts.Policy,
          Lightning.Accounts.UserNotifier,
          Lightning.Accounts.UserToken,
          Lightning.Accounts.User
        ],
        Credentials: [
          Lightning.Credentials,
          Lightning.Credentials.Credential,
          Lightning.Credentials.Policy
        ],
        Invocation: [
          Lightning.Invocation,
          Lightning.Invocation.Dataclip,
          Lightning.Invocation.Event,
          Lightning.Invocation.Run
        ],
        Pipeline: [
          Lightning.Pipeline,
          Lightning.Pipeline.Runner,
          Lightning.Pipeline.StateAssembler
        ],
        Jobs: [
          Lightning.Jobs,
          Lightning.Jobs.Job,
          Lightning.Jobs.Query,
          Lightning.Jobs.Trigger
        ],
        Projects: [
          Lightning.Projects,
          Lightning.Projects.Project,
          Lightning.Projects.Policy,
          Lightning.Projects.ProjectCredential,
          Lightning.Projects.ProjectUser
        ]
      ]
    ]
  end
end
