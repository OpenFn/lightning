defmodule Lightning.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application
  import Cachex.Spec

  require Logger

  @impl true
  def start(_type, _args) do
    # Initialize ETS table for adapter lookup
    :ets.new(:adapter_lookup, [:named_table, :public, read_concurrency: true])

    :ets.insert(
      :adapter_lookup,
      {"googlesheets", Lightning.AuthProviders.Google}
    )

    :ets.insert(
      :adapter_lookup,
      {"salesforce_oauth", Lightning.AuthProviders.Salesforce}
    )

    :opentelemetry_cowboy.setup()
    OpentelemetryPhoenix.setup(adapter: :cowboy2)
    OpentelemetryEcto.setup([:lightning, :repo])
    OpentelemetryLiveView.setup()
    OpentelemetryOban.setup(trace: [:jobs])
    # mnesia startup
    :mnesia.stop()
    :mnesia.create_schema([node()])
    :mnesia.start()
    Hammer.Backend.Mnesia.create_mnesia_table(disc_copies: [node()])
    :mnesia.wait_for_tables([:__hammer_backend_mnesia], 60_000)

    # Only add the Sentry backend if a dsn is provided.
    if Application.get_env(:sentry, :dsn),
      do: Logger.add_backend(Sentry.LoggerBackend)

    adaptor_registry_childspec =
      {Lightning.AdaptorRegistry,
       Application.get_env(:lightning, Lightning.AdaptorRegistry, [])}

    adaptor_service_childspec =
      {Lightning.AdaptorService,
       [name: :adaptor_service]
       |> Keyword.merge(Application.get_env(:lightning, :adaptor_service, []))}

    auth_providers_cache_childspec =
      {Cachex,
       name: :auth_providers,
       warmers: [
         warmer(module: Lightning.AuthProviders.CacheWarmer)
       ]}

    events = [
      [:oban, :circuit, :open],
      [:oban, :circuit, :trip],
      [:oban, :job, :exception]
    ]

    :telemetry.attach_many(
      "oban-errors",
      events,
      &Lightning.ObanManager.handle_event/4,
      nil
    )

    :ok = Oban.Telemetry.attach_default_logger(:debug)

    topologies =
      if System.get_env("K8S_HEADLESS_SERVICE") do
        [
          k8s: [
            strategy: Cluster.Strategy.Kubernetes.DNS,
            config: [
              service: System.get_env("K8S_HEADLESS_SERVICE"),
              application_name: "lightning",
              polling_interval: 5_000
            ]
          ]
        ]
      else
        Application.get_env(:libcluster, :topologies)
      end

    children = [
      Lightning.PromEx,
      {Cluster.Supervisor, [topologies, [name: Lightning.ClusterSupervisor]]},
      {Lightning.Vault, Application.get_env(:lightning, Lightning.Vault, [])},
      # Start the Ecto repository
      Lightning.Repo,
      # Start Oban,
      {Oban, oban_opts()},
      # Start the Telemetry supervisor
      LightningWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Lightning.PubSub},
      {Finch, name: Lightning.Finch},
      auth_providers_cache_childspec,
      # Start the Endpoint (http/https)
      LightningWeb.Endpoint,
      adaptor_registry_childspec,
      adaptor_service_childspec,
      {Lightning.TaskWorker, name: :cli_task_worker},
      {Lightning.Runtime.RuntimeManager,
       worker_secret: Lightning.Config.worker_secret()},
      {Lightning.KafkaTriggers.Supervisor, type: :supervisor}
      # Start a worker by calling: Lightning.Worker.start_link(arg)
      # {Lightning.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lightning.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LightningWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @impl true
  def prep_stop(state) do
    # gets saved pid instead of waiting for GenServer reply
    with os_pid when is_integer(os_pid) <-
           :persistent_term.get(:runtime_os_pid, nil),
         {pid_tree_lines, 0} <-
           System.cmd("ps", ["-s", "#{os_pid}", "-o", "pid="]) do
      node_pid =
        pid_tree_lines
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> List.last()
        |> then(&String.trim/1)

      _res = System.cmd("kill", ["-TERM", node_pid])
    end

    state
  end

  def oban_opts do
    opts = Application.get_env(:lightning, Oban)

    opts[:plugins]
    |> List.keyfind(Oban.Plugins.Cron, 0)
    |> then(fn {mod, cron_opts} ->
      {mod, put_usage_tracking_cron_opts(cron_opts)}
    end)

    opts
  end

  defp put_usage_tracking_cron_opts(cron_opts) do
    usage_tracking_opts = Lightning.Config.usage_tracking()

    if usage_tracking_opts[:enabled] do
      print_tracking_thanks_message()
    else
      print_tracking_opt_out_message()
    end

    Keyword.merge(
      cron_opts,
      [crontab: Lightning.Config.usage_tracking_cron_opts()],
      fn _key, old, new -> old ++ new end
    )
  end

  @about_anonymous_public_impact_tracking """
  OpenFn is a free and open-source Digital Public Good.
  Even if you are unable to contribute to the movement financially or by participating
  in our product development community, sending these anonymous aggregate usage reports
  will ensure the long-term sustainability of the project by allowing us
  to understand the needs of our users, by better demonstrating our impact,
  and by helping us secure further donor support.

  View the aggregated anonymous public metrics submitted by other OpenFn
  instance administrators like you from around the world here:

  https://analytics.openfn.org/public/dashboard/d4d7766e-e2fe-4673-b4e5-8bf52f0054a1
  """

  defp print_tracking_thanks_message do
    Logger.notice("""
    ️❤️ Thank you for participating in anonymous public impact reporting!

    #{@about_anonymous_public_impact_tracking}
    You are reporting to #{Lightning.Config.usage_tracking()[:host]}.
    If you would like to opt-out of anonymous public impact reporting,
    you can set your `USAGE_TRACKING_ENABLED` environment variable to `false` at any time.
    """)
  end

  defp print_tracking_opt_out_message do
    Logger.notice("""
    You have opted-out of anonymous public impact reporting.

    #{@about_anonymous_public_impact_tracking}
    If the product is benefitting you or your organization, we hope you
    will consider opting-in to anonymous public impact reporting in the future.

    You can do so by setting your `USAGE_TRACKING_ENABLED` environment variable to `true` at any time.
    """)
  end
end
