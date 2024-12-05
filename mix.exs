defmodule Lightning.MixProject do
  use Mix.Project

  def project do
    [
      app: :lightning,
      version: "2.10.5",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [
        warnings_as_errors: true
      ],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix],
        plt_local_path: "priv/plts/",
        plt_core_path: "priv/plts/core.plt"
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.post": :test,
        "test.watch": :test,
        coveralls: :test,
        verify: :test
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
      {:bcrypt_elixir, "~> 3.2"},
      {:bodyguard, "~> 2.2"},
      {:broadway_kafka, "~> 0.4.2"},
      {:bypass, "~> 2.1", only: :test},
      {:briefly, "~> 0.5.0"},
      {:cachex, "~> 3.4"},
      {:cloak_ecto, "~> 1.3.0"},
      {:credo, "~> 1.7.3", only: [:test, :dev]},
      {:crontab, "~> 1.1"},
      {:dialyxir, "~> 1.4.5", only: [:test, :dev], runtime: false},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.8.2"},
      {:ecto_sql, "~> 3.11"},
      {:esbuild, "~> 0.3", runtime: Mix.env() == :dev},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:ex_json_schema, "~> 0.9.1"},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:excoveralls, "~> 0.18.0", only: [:test, :dev]},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.18"},
      {:google_api_storage, "~> 0.40.1"},
      {:hackney, "~> 1.18"},
      {:heroicons, "~> 0.5.3"},
      {:httpoison, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:joken, "~> 2.6.0"},
      {:jsonpatch, "~> 1.0.2"},
      {:junit_formatter, "~> 3.0", only: [:test]},
      {:libcluster, "~> 3.3"},
      {:mimic, "~> 1.10.2", only: :test},
      {:mix_test_watch, "~> 1.2.0", only: [:test, :dev], runtime: false},
      {:mock, "~> 0.3.8", only: :test},
      {:mox, "~> 1.2.0", only: :test},
      {:oauth2, "~> 2.1"},
      {:oban, "~> 2.18"},
      {:opentelemetry_exporter, "~> 1.6.0"},
      {:opentelemetry, "~> 1.3.1"},
      {:opentelemetry_api, "~> 1.2.2"},
      {:opentelemetry_cowboy, "~> 0.2.1"},
      {:opentelemetry_ecto, "~> 1.1.1"},
      {:opentelemetry_liveview, "~> 1.0.0-rc.4"},
      {:opentelemetry_oban, "~> 1.0.0"},
      {:opentelemetry_phoenix, "~> 1.1.1"},
      {:opentelemetry_tesla, "~> 2.2.0"},
      {:petal_components, "~> 2.5"},
      {:phoenix, "~> 1.7.11"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 0.20.5"},
      {:phoenix_storybook, "~> 0.6.4", only: :dev},
      {:cors_plug, "~> 3.0"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:prom_ex, "~> 1.9.0"},
      {:rambo, "~> 0.3.4"},
      {:retry, "~> 0.18"},
      {:scrivener, "~> 2.7"},
      {:sentry, "~> 10.8"},
      {:sobelow, "~> 0.13.0", only: [:test, :dev]},
      {:sweet_xml, "~> 0.7.1", only: [:test]},
      {:swoosh, "~> 1.17"},
      {:gen_smtp, "~> 1.1"},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:tesla, "~> 1.13"},
      {:timex, "~> 3.7"},
      {:unplug, "~> 1.0"},
      {:replug, "~> 0.1.0"},
      {:phoenix_swoosh, "~> 1.2.1"},
      {:hammer_backend_mnesia, "~> 0.6"},
      {:hammer, "~> 6.0"},
      {:dotenvy, "~> 0.8.0"},
      {:goth, "~> 1.3"},
      {:gcs_signed_url, "~> 0.4.6"},
      {:packmatic, "~> 1.2"},
      # MFA
      {:nimble_totp, "~> 1.0"},
      {:eqrcode, "~> 0.1"},
      # Github API Secret Encoding
      {:enacl, github: "aeternity/enacl", branch: "master"},
      {:earmark, "~> 1.4"},
      {:eventually, "~> 1.1", only: [:test]},
      {:benchee, "~> 1.3.1", only: :dev},
      {:statistics, "~> 0.6", only: :dev}
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
      "ecto.setup": ["ecto.create", "ecto.migrate"],
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
        "RUNNINGLOCAL.md": [title: "Running Locally"],
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
        Config: [
          ~r/Lightning.Config/
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
          ~r/Lightning.Graph/,
          ~r/Lightning./
        ]
      ]
    ]
  end
end
