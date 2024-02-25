defmodule Lightning.MixProject do
  use Mix.Project

  def project do
    [
      app: :lightning,
      version: "2.0.5",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [
        warnings_as_errors: true
      ],
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix],
        plt_local_path: "priv/plts/"
      ],
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
    |> then(fn project ->
      if System.get_env("UMBRELLA") == "true" do
        project ++
          [
            build_path: "../../_build",
            config_path: "../../config/config.exs",
            deps_path: "../../deps",
            lockfile: "../../mix.lock"
          ]
      else
        project
      end
    end)
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Lightning.Application, [:timex]},
      extra_applications: [:logger, :runtime_tools, :os_mon, :scrivener]
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
      # {:rexbug, ">= 1.0.0", only: :test},
      {:bcrypt_elixir, "~> 2.0"},
      {:bodyguard, "~> 2.2"},
      {:bypass, "~> 2.1"},
      {:cachex, "~> 3.4"},
      {:cloak_ecto, "~> 1.2.0"},
      {:credo, "~> 1.7.3", only: [:test, :dev]},
      {:crontab, "~> 1.1"},
      {:dialyxir, "~> 1.4.2", only: [:test, :dev], runtime: false},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.7.14"},
      {:ecto_sql, "~> 3.6"},
      {:esbuild, "~> 0.3", runtime: Mix.env() == :dev},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:ex_json_schema, "~> 0.9.1"},
      {:ex_machina, "~> 2.7.0", only: :test},
      {:excoveralls, "~> 0.15.0", only: [:test, :dev]},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.18"},
      {:hackney, "~> 1.18"},
      {:heroicons, "~> 0.5.3"},
      {:httpoison, "~> 1.8"},
      {:jason, "~> 1.4"},
      {:joken, "~> 2.6.0"},
      {:jsonpatch, "~> 1.0.2"},
      {:junit_formatter, "~> 3.0", only: [:test]},
      {:libcluster, "~> 3.3"},
      {:mimic, "~> 1.7.2", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:test, :dev], runtime: false},
      {:mock, "~> 0.3.8", only: :test},
      {:mox, "~> 1.0.2", only: :test},
      {:oauth2, "~> 2.1"},
      {:oban, "~> 2.13"},
      {:opentelemetry_exporter, "~> 1.6.0"},
      {:opentelemetry, "~> 1.3.1"},
      {:opentelemetry_api, "~> 1.2.2"},
      {:opentelemetry_cowboy, "~> 0.2.1"},
      {:opentelemetry_ecto, "~> 1.1.1"},
      {:opentelemetry_liveview, "~> 1.0.0-rc.4"},
      {:opentelemetry_oban, "~> 1.0.0"},
      {:opentelemetry_phoenix, "~> 1.1.1"},
      {:opentelemetry_tesla, "~> 2.2.0"},
      {:petal_components, "~> 1.2.0"},
      {:phoenix, "~> 1.7.11"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.5"},
      {:phoenix_storybook, "~> 0.5.2"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:prom_ex, "~> 1.8.0"},
      {:rambo, "~> 0.3.4"},
      {:scrivener, "~> 2.7"},
      {:sentry, "~> 8.0"},
      {:sobelow, "~> 0.13.0", only: [:test, :dev]},
      {:sweet_xml, "~> 0.7.1", only: [:test]},
      {:swoosh, "~> 1.9"},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:temp, "~> 0.4"},
      {:tesla, "~> 1.4"},
      {:timex, "~> 3.7"},
      {:unplug, "~> 1.0"},
      {:replug, "~> 0.1.0"},
      {:phoenix_swoosh, "~> 1.0"},
      {:hammer_backend_mnesia, "~> 0.6"},
      {:hammer, "~> 6.0"},
      {:vapor, "~> 0.10.0"},
      # MFA
      {:nimble_totp, "~> 1.0"},
      {:eqrcode, "~> 0.1"}
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
      setup: [
        "deps.get",
        "tailwind.install --if-missing",
        "esbuild.install --if-missing",
        "lightning.install_runtime",
        "lightning.install_adaptor_icons",
        "lightning.install_schemas",
        "ecto.setup"
      ],
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
        "credo --strict --all",
        "sobelow"
      ]
    ]
  end

  defp docs do
    [
      # The main page in the docs
      main: "readme",
      logo: "priv/static/images/square-logo.png",
      extras: [
        "README.md": [title: "Lightning"],
        "DEPLOYMENT.md": [title: "Deployment"],
        "benchmarking/README.md": [
          title: "Benchmarking",
          filename: "benchmarking.md"
        ],
        "WORKERS.md": [title: "Workers"],
        "PROVISIONING.md": [title: "Provisioning"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      source_url: "https://github.com/OpenFn/lightning",
      homepage_url: "https://openfn.github.io/Lightning",
      groups_for_modules: [
        Accounts: [
          ~r/Lightning.Accounts/
        ],
        Runs: [
          ~r/Lightning.Runs/
        ],
        WorkOrders: [
          ~r/Lightning.WorkOrders/
        ],
        Credentials: [
          ~r/Lightning.Credentials/
        ],
        Invocations: [
          ~r/Lightning.Invocation/
        ],
        Pipeline: [
          ~r/Lightning.Pipeline/
        ],
        Jobs: [
          ~r/Lightning.Jobs/
        ],
        Projects: [
          ~r/Lightning.Projects/
        ],
        Runtime: [
          ~r/Lightning.Runtime/
        ],
        Workflows: [
          ~r/Lightning.Workflow/
        ],
        "Custom Data Types": [
          ~r/Lightning.LogMessage/,
          ~r/Lightning.UnixDateTime/
        ],
        Web: [
          ~r/LightningWeb/
        ],
        Other: [
          ~r/Lightning.Graph/
        ]
      ]
    ]
  end
end
