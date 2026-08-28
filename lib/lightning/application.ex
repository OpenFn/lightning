defmodule Lightning.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application
  import Cachex.Spec

  require Logger

  @impl true
  def start(_type, _args) do
    # mnesia startup
    :mnesia.stop()
    :mnesia.create_schema([node()])
    :mnesia.start()
    Hammer.Backend.Mnesia.create_mnesia_table(disc_copies: [node()])
    :mnesia.wait_for_tables([:__hammer_backend_mnesia], 60_000)

    # Only add the Sentry logger handler if a dsn is provided.
    if Application.get_env(:sentry, :dsn) do
      :logger.add_handler(:sentry_error_handler, Sentry.LoggerHandler, %{
        config: %{
          metadata: [:file, :line, :prompt_size, :session_id],
          rate_limiting: [max_events: 10, interval: _1_second = 1_000],
          capture_log_messages: true,
          level: :error
        }
      })
    end

    # :logger.add_handler(:file_log, :logger_std_h, %{
    #   level: :warning,
    #   config: %{
    #     file: ~c"log/lightning.log",
    #     max_no_bytes: 10_000_000,
    #     max_no_files: 5,
    #     compress_on_rotate: true
    #   },
    #   formatter: Logger.Formatter.new()
    # })

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

    # Signing keys (JWKS) for OIDC login, cached off the per-login verify path.
    auth_provider_jwks_cache_childspec =
      Supervisor.child_spec({Cachex, name: :auth_provider_jwks},
        id: :auth_provider_jwks_cache
      )

    :telemetry.attach_many(
      "oban-job-exception",
      [[:oban, :job, :exception]],
      &Lightning.ObanManager.handle_event/4,
      nil
    )

    # Separate handler id from the exception one. :telemetry detaches a handler
    # from every event in its attach_many the first time it raises, so sharing an
    # id would let one bad :stop take exception reporting down with it until the
    # next restart.
    :telemetry.attach_many(
      "oban-job-stop",
      [[:oban, :job, :stop]],
      &Lightning.ObanManager.handle_event/4,
      nil
    )

    :telemetry.attach_many(
      "swoosh-mailer",
      [[:swoosh, :deliver, :stop]],
      &Lightning.Mailer.EventHandler.handle_event/4,
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

    distributed_erlang_config =
      Application.get_env(:lightning, :distributed_erlang)

    topologies =
      topologies
      |> add_additional_libcluster_topology(
        Keyword.fetch!(
          distributed_erlang_config,
          :node_discovery_via_postgres_enabled
        ),
        Keyword.fetch!(
          distributed_erlang_config,
          :node_discovery_via_postgres_channel_name
        )
      )

    goth =
      Application.get_env(:lightning, Lightning.Google, [])
      |> then(fn config ->
        if config[:required] do
          {Goth,
           name: Lightning.Google,
           source:
             {:service_account, config[:credentials],
              [
                scopes: [
                  "openid",
                  "https://www.googleapis.com/auth/userinfo.email",
                  "https://www.googleapis.com/auth/cloud-platform"
                ]
              ]}}
        end
      end)

    children =
      [
        Lightning.PromEx,
        {Cluster.Supervisor, [topologies, [name: Lightning.ClusterSupervisor]]},
        {Lightning.Vault, Application.get_env(:lightning, Lightning.Vault, [])},
        # Start the Ecto repository
        Lightning.Repo,
        # Start Oban,
        {Oban, oban_opts()},
        goth,
        # Start the Telemetry supervisor
        LightningWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: Lightning.PubSub},
        {Finch, name: Lightning.Finch, pools: apollo_pools()},
        auth_providers_cache_childspec,
        auth_provider_jwks_cache_childspec,
        {Lightning.Collaboration.Supervisor, []},
        # Start the Endpoint (http/https)
        LightningWeb.Endpoint,
        Lightning.Workflows.Presence,
        LightningWeb.WorkerPresence,
        adaptor_service_childspec,
        {Lightning.Adaptors.Supervisor, name: Lightning.Adaptors},
        {Lightning.TaskWorker, name: :cli_task_worker},
        {Lightning.Runtime.RuntimeManager,
         worker_secret: Lightning.Config.worker_secret(),
         endpoint: LightningWeb.Endpoint}
        # Start a worker by calling: Lightning.Worker.start_link(arg)
        # {Lightning.Worker, arg}
      ]
      |> Enum.reject(&is_nil/1)

    warn_if_apollo_timeout_still_set()
    warn_if_connect_timeout_is_unreachable()
    warn_if_ai_jobs_outlive_the_drain_window()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lightning.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Size, count and protocol restate Finch's own defaults, so this changes
  # nothing as shipped. It exists to give APOLLO_CONNECT_TIMEOUT_MS somewhere to
  # take effect, and to pin http1: :request_timeout is HTTP/1-only, and on http2
  # receive_timeout becomes a whole-request deadline instead of the gap between
  # chunks, which would silently cap how long an answer may be.
  @doc false
  def apollo_pools do
    base = %{default: [size: 50, count: 1]}

    endpoint = Lightning.Config.apollo(:endpoint)

    if poolable_url?(endpoint) do
      Map.put(base, endpoint,
        protocols: [:http1],
        size: 50,
        count: 1,
        conn_opts: [
          transport_opts: [timeout: Lightning.Config.apollo(:connect_timeout)]
        ]
      )
    else
      base
    end
  end

  # Finch raises on a key it cannot parse, which would take the node down at
  # boot over a misconfigured endpoint. Everywhere else treats one of those as
  # the assistant simply being switched off, so match that.
  defp poolable_url?(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp poolable_url?(_endpoint), do: false

  # Reaching Apollo happens inside the adapter's wait for the first byte, so a
  # connect timeout above the idle one can never expire.
  @doc false
  def warn_if_connect_timeout_is_unreachable do
    connect = Lightning.Config.apollo(:connect_timeout)
    idle = Lightning.Config.apollo(:idle_timeout)

    if is_integer(connect) and is_integer(idle) and connect > idle do
      Logger.warning("""
      [AI Assistant] APOLLO_CONNECT_TIMEOUT_MS is #{connect}ms but \
      APOLLO_IDLE_TIMEOUT_MS is #{idle}ms, and the wait to reach Apollo sits \
      inside the idle budget. Connecting will give up after #{idle}ms whatever \
      the connect setting says. Raise APOLLO_IDLE_TIMEOUT_MS to at least \
      #{connect}ms, or lower APOLLO_CONNECT_TIMEOUT_MS.
      """)
    end
  end

  # Left unread it would silently lift a ceiling an operator lowered on purpose.
  @doc false
  def warn_if_apollo_timeout_still_set do
    if Application.get_env(:lightning, :apollo_timeout_env_still_set) do
      Logger.warning("""
      [AI Assistant] APOLLO_TIMEOUT is no longer read and the value you set is \
      being ignored. It is replaced by APOLLO_CONNECT_TIMEOUT_MS, \
      APOLLO_IDLE_TIMEOUT_MS and APOLLO_REQUEST_TIMEOUT_MS.
      """)
    end
  end

  # Oban stops its producer before killing what is still running, so a job that
  # outlives the window dies with nothing left to report it and its message sits
  # :processing until the reaper finds it.
  @doc false
  def warn_if_ai_jobs_outlive_the_drain_window do
    grace = Application.get_env(:lightning, Oban)[:shutdown_grace_period]
    ceiling = Lightning.AiAssistant.MessageProcessor.job_timeout()

    if is_integer(grace) and is_integer(ceiling) and ceiling >= grace do
      Logger.warning("""
      [AI Assistant] An AI job may run for #{ceiling}ms but Oban stops draining \
      after #{grace}ms. A deploy landing on a running job will kill it without \
      emitting telemetry, leaving its message :processing until the reaper runs.
      Lower APOLLO_CONNECT_TIMEOUT_MS, APOLLO_IDLE_TIMEOUT_MS or \
      APOLLO_REQUEST_TIMEOUT_MS. Oban's shutdown_grace_period is the other side \
      of this, but it is compiled in rather than read from the environment.
      """)
    end
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

  @impl true
  def start_phase(:seed_prom_ex_telemetry, :normal, _) do
    Lightning.PromEx.seed_event_metrics()
    :ok
  end

  def oban_opts do
    opts = Application.get_env(:lightning, Oban)

    {_keyword, new_opts} =
      opts[:plugins]
      |> List.keyfind(Oban.Plugins.Cron, 0)
      |> then(fn {mod, cron_opts} ->
        {mod, put_usage_tracking_cron_opts(cron_opts)}
      end)

    updated_plugins =
      opts[:plugins]
      |> Keyword.merge([{Oban.Plugins.Cron, new_opts}])

    opts |> Keyword.put(:plugins, updated_plugins)
  end

  defp put_usage_tracking_cron_opts(cron_opts) do
    usage_tracking_opts = Lightning.Config.usage_tracking()

    if Lightning.Config.env() !== :test do
      if usage_tracking_opts[:enabled] do
        print_tracking_thanks_message()
      else
        print_tracking_opt_out_message()
      end
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

  def add_additional_libcluster_topology(
        topologies,
        false = _postgres_discovery_enabled,
        _channel_name
      ) do
    topologies
  end

  def add_additional_libcluster_topology(
        topologies,
        true = _postgres_discovery_enabled,
        channel_name
      ) do
    Keyword.merge(
      topologies,
      postgres: [
        strategy: LibclusterPostgres.Strategy,
        config:
          Keyword.merge(Lightning.Repo.config(),
            channel_name: channel_name
          )
      ]
    )
  end
end
