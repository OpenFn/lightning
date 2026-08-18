defmodule Lightning.MixProject do
  use Mix.Project

  def project do
    [
      app: :lightning,
      version: "2.18.0-pre2",
      elixir: "~> 1.18",
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
        "coveralls.json": :test,
        "test.watch": :test,
        coveralls: :test,
        verify: :test
      ],
      compilers: Mix.compilers(),
      hex: hex_audit(),

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
      extra_applications: [:logger, :runtime_tools, :os_mon, :scrivener],
      start_phases: [seed_prom_ex_telemetry: []]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Advisories acknowledged for `mix hex.audit`. cowlib is the only one left, and
  # it has no patched release (latest is 2.19.0). Note that both EEF records carry
  # no `fixed` event, while the GitHub twin of CVE-2026-43969
  # (GHSA-g2wm-735q-3f56) records `last_affected: 2.16.1` -- so 2.19.0 may
  # already be unaffected and the EEF record simply lacks a fix event. IDs are
  # matched against an advisory's primary ID or any alias, so the CVE form also
  # silences the GHSA/EEF variants.
  defp hex_audit do
    [
      ignore_advisories: [
        # cowlib
        "CVE-2026-43966",
        "CVE-2026-43969"
      ]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # {:rexbug, ">= 1.0.0", only: :test},
      {:bcrypt_elixir, "~> 3.3"},
      {:bodyguard, "~> 2.2"},
      {:broadway_kafka, "~> 0.4.2"},
      {:bypass, "~> 2.1", only: :test},
      {:briefly, "~> 0.5.0"},
      {:cachex, "~> 4.0"},
      {:castore, "~> 1.0"},
      {:cloak_ecto, "~> 1.3.0"},
      {:credo, "~> 1.7.3", only: [:test, :dev]},
      {:crontab, "~> 1.1"},
      {:dialyxir, "~> 1.4.5", only: [:test, :dev], runtime: false},
      # Ecto pins ~> 2.0, but decimal 3.0 is API-compatible and patches
      # GHSA-rhv4-8758-jx7v (unbounded exponent DoS in `Decimal.new`).
      {:decimal, "~> 3.0", override: true},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.8.2"},
      {:ecto_sql, "~> 3.13"},
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:ex_json_schema, "~> 0.11.2"},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:excoveralls, "~> 0.18.5", only: [:test, :dev]},
      {:finch, "~> 0.23"},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.26"},
      {:git_hooks, "~> 0.9.0", only: [:dev], runtime: false},
      # Overridden because phoenix_swoosh 1.2.1 (latest) still declares
      # hackney ~> 1.10. It never actually calls hackney, so the constraint is
      # dead weight, but it has to be overridden to resolve.
      # 4.6.0 is the ceiling: 4.6.1+ require h2 ~> 0.11.0 while hackney's own
      # webtransport dep requires h2 ~> 0.10.4, so newer releases cannot resolve.
      {:hackney, "~> 4.6.0", override: true},
      {:heroicons, "~> 0.5.3"},
      {:httpoison, "~> 3.0.0", override: true},
      {:jason, "~> 1.4"},
      {:joken, "~> 2.6.0"},
      {:jsonpatch, "~> 2.2"},
      {:junit_formatter, "~> 3.0", only: [:test]},
      {:libcluster, "~> 3.3"},
      {:libcluster_postgres, "~> 0.2.0"},
      {:live_debugger, "~> 0.3.0", only: :dev},
      {:mimic, "~> 1.12.0", only: :test},
      {:mint, "~> 1.0"},
      {:mix_test_watch, "~> 1.2.0", only: [:test, :dev], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.8", only: :test},
      {:mox, "~> 1.2.0", only: :test},
      {:oauth2, "~> 2.1"},
      {:oban, "~> 2.19"},
      {:petal_components, "~> 3.0"},
      {:phoenix, "~> 1.7.11"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0.17"},
      {:cors_plug, "~> 3.0"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:prom_ex, "~> 1.11.0"},
      {:rambo, "~> 0.3.4"},
      {:retry, "~> 0.18"},
      {:scrivener, "~> 2.7"},
      {:sentry, "~> 13.2.0"},
      {:sobelow, "~> 0.14.1", only: [:test, :dev]},
      {:sweet_xml, "~> 0.7.1", only: [:test]},
      {:swoosh, "~> 1.26"},
      {:gen_smtp, "~> 1.1"},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:tesla, "~> 1.18.2"},
      {:tidewave, "~> 0.8.0", only: :dev},
      {:timex, "~> 3.7"},
      # Pinned to the merge of `hackney ~> 1.17 or ~> 4.0` (lau/tzdata#170),
      # which lets tzdata keep its autoupdater on hackney 4. Not on Hex yet --
      # 1.1.4 predates the fix and no release is scheduled. Move back to a Hex
      # release once one carries #170, since git deps are invisible to
      # `mix deps.audit`.
      {:tzdata,
       github: "lau/tzdata",
       ref: "766f38de21e9cd3dc4b185ac6244466e4ee65308",
       override: true},
      {:replug, "~> 0.1.0"},
      {:phoenix_swoosh, "~> 1.2.1"},
      {:hammer_backend_mnesia, "~> 0.6"},
      {:hammer, "~> 6.0"},
      {:dotenvy, "~> 1.1.0"},
      {:goth, "~> 1.3"},
      {:gcs_signed_url, "~> 0.4.6"},
      {:packmatic, "~> 1.2"},
      # MFA
      {:nimble_totp, "~> 1.0"},
      {:eqrcode, "~> 0.2"},
      # Github API Secret Encoding
      {:enacl, github: "aeternity/enacl", branch: "master"},
      {:mdex, "~> 0.13"},
      {:eventually, "~> 1.1", only: [:test]},
      {:benchee, "~> 1.5.0", only: :dev},
      {:statistics, "~> 0.6", only: :dev},
      {:tls_certificate_check, "~> 1.32"},
      philter_dep(),
      {:y_ex, "~> 0.8.0"},
      {:chameleon, "~> 2.5"}
    ]
  end

  defp philter_dep do
    if path = System.get_env("PHILTER_PATH") do
      {:philter, path: path}
    else
      {:philter, "~> 0.4.0"}
    end
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
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing"
      ],
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
      ],
      compile: [
        "compile --warnings-as-errors"
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
        "tooling/benchmarking/README.md": [
          title: "Benchmarking",
          filename: "benchmarking.md"
        ],
        "WORKERS.md": [title: "Workers"],
        "PROVISIONING.md": [title: "Provisioning"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      source_url: "https://github.com/OpenFn/lightning",
      homepage_url: "https://openfn.github.io/lightning",
      groups_for_modules: [
        API: [
          ~r/LightningWeb.API/
        ],
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
