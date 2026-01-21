defmodule Lightning.Config.Bootstrap do
  @moduledoc """
  Bootstrap the application environment.

  This module is responsible for setting up the application environment based on
  the configuration provided by the user.

  Usually, config calls are made in the `config/runtime.exs` file. This module
  abstracts the runtime configuration into a module that can be tested and
  called from other places (aside from `config/runtime.exs`) file.

  > #### Sourcing envs {: .info}
  >
  > Internally this module uses `Dotenvy.source/1` to source environment variables
  > from the `.env`, `.env.<config_env>`, and `.env.<config_env>.override` files.
  > It also sources the system environment variables.
  >
  > Calling `configure/0` without calling `source_envs/0` or `Dotenvy.source/2`
  > first will result in no environment variables being loaded.

  Usage:

  ```elixir
  Lightning.Config.Bootstrap.source_envs()
  Lightning.Config.Bootstrap.configure()
  ```
  """

  import Config
  import Dotenvy

  alias Lightning.Config.Utils

  def source_envs do
    {:ok, _} =
      source([
        ".env",
        ".#{config_env()}.env",
        ".#{config_env()}.override.env",
        System.get_env()
      ])
  end

  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  def configure do
    unless Process.get(:dotenvy_vars) do
      raise """
      Environment variables haven't been sourced first.
      Please call `source_envs/0` before calling `configure/0`.
      """
    end

    if config_env() == :dev do
      enabled = env!("LIVE_DEBUGGER", &Utils.ensure_boolean/1, true)
      config :live_debugger, :disabled?, not enabled
    end

    # Load storage and webhook retry config early so endpoint can respect it.
    setup_storage()
    setup_webhook_retry()

    # Merge the configuration from the existing application environment into
    # this processes config dictionary.
    # Without this, values set in the application environment previously
    # via `confix.exs` and others won't be available in the current process,
    # and must be fetched via `Application.get_env/2` or `Utils.get_env/2`.
    # config :lightning, Application.get_all_env(:lightning)

    # Start the phoenix server if environment is set and running in a release
    if env!("PHX_SERVER", :boolean, false) &&
         env!("RELEASE_NAME", :boolean, false) do
      config :lightning, LightningWeb.Endpoint, server: true
    end

    config :lightning,
           :is_resettable_demo,
           env!(
             "IS_RESETTABLE_DEMO",
             &Utils.ensure_boolean/1,
             Application.fetch_env!(:lightning, :is_resettable_demo)
           )

    config :lightning,
           :default_retention_period,
           env!(
             "DEFAULT_RETENTION_PERIOD",
             :integer,
             Application.fetch_env!(:lightning, :default_retention_period)
           )

    github_config = github_config()
    config :lightning, :github_app, github_config

    config :lightning,
      repo_connection_signing_secret:
        env!(
          "REPO_CONNECTION_SIGNING_SECRET",
          :string,
          Utils.get_env([:lightning, :repo_connection_signing_secret])
        )
        |> tap(fn v ->
          if is_nil(v) and Enum.all?(github_config |> Keyword.values()) do
            raise """
            REPO_CONNECTION_SIGNING_SECRET not set

            Please provide a secret, or use `mix lightning.gen_encryption_key` to generate one.
            """
          end
        end)

    config :lightning, :apollo,
      endpoint:
        env!(
          "APOLLO_ENDPOINT",
          :string,
          Utils.get_env([:lightning, :apollo, :endpoint])
        ),
      timeout:
        env!(
          "APOLLO_TIMEOUT",
          :integer,
          Utils.get_env([:lightning, :apollo, :timeout])
        ),
      ai_assistant_api_key: env!("AI_ASSISTANT_API_KEY", :string, nil)

    config :lightning, Lightning.Runtime.RuntimeManager,
      start:
        env!(
          "RTM",
          &Utils.ensure_boolean/1,
          Utils.get_env([:lightning, Lightning.Runtime.RuntimeManager, :start])
        ),
      port:
        env!(
          "RTM_PORT",
          :integer,
          Utils.get_env(
            [:lightning, Lightning.Runtime.RuntimeManager, :port],
            2222
          )
        )

    config :lightning, :workers,
      private_key:
        env!(
          "WORKER_RUNS_PRIVATE_KEY",
          fn encoded ->
            encoded
            |> Base.decode64(padding: false)
            |> case do
              {:ok, pem} -> pem
              :error -> raise "Could not decode PEM"
            end
          end,
          Utils.get_env([:lightning, :workers, :private_key])
        )
        |> tap(fn v ->
          unless v do
            raise "No worker private key found, please set WORKER_RUNS_PRIVATE_KEY"
          end
        end)
        |> tap(&validate_rsa_key!/1),
      worker_secret:
        env!(
          "WORKER_SECRET",
          :string!,
          Utils.get_env([:lightning, :workers, :worker_secret])
        )
        |> tap(fn v ->
          unless v do
            raise "No worker secret found, please set WORKER_SECRET"
          end
        end)

    release = release_info()

    config :lightning, :release, release

    config :lightning, :adaptor_service,
      adaptors_path: env!("ADAPTORS_PATH", :string, "./priv/openfn")

    local_adaptors_repo =
      env!(
        "OPENFN_ADAPTORS_REPO",
        :string,
        Utils.get_env([
          :lightning,
          Lightning.AdaptorRegistry,
          :local_adaptors_repo
        ])
      )

    use_local_adaptors_repo? =
      env!("LOCAL_ADAPTORS", &Utils.ensure_boolean/1, false)
      |> tap(fn v ->
        if v && !is_binary(local_adaptors_repo) do
          raise """
          LOCAL_ADAPTORS is set to true, but OPENFN_ADAPTORS_REPO is not set.
          """
        end
      end)

    config :lightning, Lightning.AdaptorRegistry,
      use_cache:
        env!(
          "ADAPTORS_REGISTRY_JSON_PATH",
          :string,
          Utils.get_env([:lightning, Lightning.AdaptorRegistry, :use_cache])
        ),
      local_adaptors_repo:
        use_local_adaptors_repo? && Path.expand(local_adaptors_repo)

    config :lightning,
      schemas_path:
        env!(
          "SCHEMAS_PATH",
          :string,
          Utils.get_env([:lightning, :schemas_path], "./priv")
        )

    config :lightning,
           :purge_deleted_after_days,
           env!(
             "PURGE_DELETED_AFTER_DAYS",
             :integer,
             Utils.get_env([:lightning, :purge_deleted_after_days], 7)
           )

    config :lightning,
           :activity_cleanup_chunk_size,
           env!(
             "ACTIVITY_CLEANUP_CHUNK_SIZE",
             :integer,
             Utils.get_env([:lightning, :activity_cleanup_chunk_size], 500)
           )

    base_cron = [
      {"* * * * *", Lightning.Workflows.Scheduler},
      {"* * * * *", ObanPruner},
      {"*/5 * * * *", Lightning.Janitor},
      {"0 10 * * *", Lightning.DigestEmailWorker,
       args: %{"type" => "daily_project_digest"}},
      {"0 10 * * 1", Lightning.DigestEmailWorker,
       args: %{"type" => "weekly_project_digest"}},
      {"0 10 1 * *", Lightning.DigestEmailWorker,
       args: %{"type" => "monthly_project_digest"}},
      #  TODO - move this into an ENV?
      {"17 */2 * * *", Lightning.Projects, args: %{"type" => "data_retention"}},
      {"*/10 * * * *", Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker}
    ]

    cleanup_cron =
      if Application.get_env(:lightning, :purge_deleted_after_days) > 0,
        do: [
          {"15 2 * * *", Lightning.Accounts, args: %{"type" => "purge_deleted"}},
          {"30 2 * * *", Lightning.Credentials,
           args: %{"type" => "purge_deleted"}},
          {"45 2 * * *", Lightning.Projects, args: %{"type" => "purge_deleted"}},
          {"0 3 * * *", Lightning.WebhookAuthMethods,
           args: %{"type" => "purge_deleted"}}
        ],
        else: []

    all_cron = base_cron ++ cleanup_cron

    config :lightning, Oban,
      name: Lightning.Oban,
      repo: Lightning.Repo,
      plugins: [
        {Oban.Plugins.Cron, crontab: all_cron}
      ],
      shutdown_grace_period: :timer.minutes(2),
      dispatch_cooldown: 100,
      queues: [
        scheduler: 1,
        workflow_failures: 1,
        background: 1,
        history_exports: 1,
        ai_assistant: 10
      ]

    # https://plausible.io/ is an open-source, privacy-friendly alternative to
    # Google Analytics. Provide an src and data-domain for your script below.
    config :lightning, :plausible,
      src: env!("PLAUSIBLE_SRC", :string, nil),
      data_domain: env!("PLAUSIBLE_DATA_DOMAIN", :string, nil)

    config :lightning,
           :run_grace_period_seconds,
           env!("RUN_GRACE_PERIOD_SECONDS", :integer, 10)

    config :lightning,
           :max_run_duration_seconds,
           env!("WORKER_MAX_RUN_DURATION_SECONDS", :integer, 300)

    config :lightning,
           :max_dataclip_size_bytes,
           env!("MAX_DATACLIP_SIZE_MB", :integer, 10) * 1_000_000

    config :lightning,
           :queue_result_retention_period,
           env!("QUEUE_RESULT_RETENTION_PERIOD_MINUTES", :integer, 60)

    config :lightning,
           :allow_signup,
           env!("ALLOW_SIGNUP", &Utils.ensure_boolean/1, false)

    config :lightning,
           :init_project_for_new_user,
           env!("INIT_PROJECT_FOR_NEW_USER", &Utils.ensure_boolean/1, false)

    config :lightning,
           :require_email_verification,
           env!("REQUIRE_EMAIL_VERIFICATION", &Utils.ensure_boolean/1, false)

    config :lightning,
           :webhook_response_timeout_ms,
           env!("WEBHOOK_RESPONSE_TIMEOUT_MS", :integer, 30_000)

    # To actually send emails you need to configure the mailer to use a real
    # adapter. You may configure the swoosh api client of your choice.
    # See # https://hexdocs.pm/swoosh/Swoosh.html#module-installation for more details.
    case env!("MAIL_PROVIDER", :string, nil) do
      nil ->
        nil

      "local" ->
        config :lightning, Lightning.Mailer, adapter: Swoosh.Adapters.Local

      "mailgun" ->
        config :lightning, Lightning.Mailer,
          adapter: Swoosh.Adapters.Mailgun,
          api_key: env!("MAILGUN_API_KEY", :string),
          domain: env!("MAILGUN_DOMAIN", :string)

      "smtp" ->
        # TODO: HOW DO WE LET USERS PICK WHAT TO CONFIGURE HERE?
        # https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html#content
        config :lightning, Lightning.Mailer,
          adapter: Swoosh.Adapters.SMTP,
          username: env!("SMTP_USERNAME", :string),
          password: env!("SMTP_PASSWORD", :string),
          relay: env!("SMTP_RELAY", :string),
          tls:
            env!(
              "SMTP_TLS",
              fn v ->
                case v do
                  "true" ->
                    :always

                  "false" ->
                    :never

                  "if_available" ->
                    :if_available

                  unknown ->
                    raise """
                    Unknown SMTP_TLS value: #{unknown}

                    Must be one of: true, false, if_available
                    """
                end
              end,
              :always
            ),
          port: env!("SMTP_PORT", :integer, 587)

      unknown ->
        raise """
        Unknown mail provider: #{unknown}

        Currently supported providers are:

        - local (default)
        - mailgun
        - smtp
        """
    end

    config :lightning,
      emails: [
        sender_name: env!("EMAIL_SENDER_NAME", :string, "OpenFn"),
        admin_email:
          env!(
            "EMAIL_ADMIN",
            :string,
            get_env(:lightning, [:emails, :admin_email]) ||
              "lightning@example.com"
          )
      ]

    # Use the `PRIMARY_ENCRYPTION_KEY` env variable if available, else fall back
    # to defaults.
    # Defaults are set for `dev` and `test` modes.
    config :lightning, Lightning.Vault,
      primary_encryption_key:
        env!(
          "PRIMARY_ENCRYPTION_KEY",
          :string,
          Utils.get_env(
            [:lightning, Lightning.Vault, :primary_encryption_key],
            nil
          )
        )

    log_level =
      env!(
        "LOG_LEVEL",
        fn log_level ->
          allowed_log_levels =
            ~w[emergency alert critical error warning warn notice info debug]

          if log_level in allowed_log_levels do
            log_level |> String.to_atom()
          else
            raise Dotenvy.Error,
              message: """
              Invalid LOG_LEVEL, must be on of #{allowed_log_levels |> Enum.join(", ")}
              """
          end
        end,
        Utils.get_env([:logger, :level])
      )

    if log_level do
      config :logger, :level, log_level
    end

    database_url = env!("DATABASE_URL", :string, nil)

    config :lightning, Lightning.Repo,
      url: database_url,
      pool_size: env!("DATABASE_POOL_SIZE", :integer, 10),
      timeout: env!("DATABASE_TIMEOUT", :integer, 15_000),
      queue_target: env!("DATABASE_QUEUE_TARGET", :integer, 50),
      queue_interval: env!("DATABASE_QUEUE_INTERVAL", :integer, 1000)

    host = env!("URL_HOST", :string, "example.com")

    port =
      env!(
        "PORT",
        :integer,
        Utils.get_env([:lightning, LightningWeb.Endpoint, :http, :port])
      )

    url_port = env!("URL_PORT", :integer, 443)

    config :lightning, LightningWeb.Endpoint,
      url: [port: port],
      http: [port: port]

    config :lightning,
      cors_origin:
        env!("CORS_ORIGIN", :string, "*") |> String.split(",") |> List.wrap()

    if config_env() == :prod do
      unless database_url do
        raise """
        environment variable DATABASE_URL is missing.
        For example: ecto://USER:PASS@HOST/DATABASE
        """
      end

      maybe_ipv6 =
        if env!("ECTO_IPV6", &Utils.ensure_boolean/1, false),
          do: [:inet6],
          else: []

      disable_db_ssl = env!("DISABLE_DB_SSL", &Utils.ensure_boolean/1, false)

      config :lightning, Lightning.Repo,
        url: database_url,
        socket_options: maybe_ipv6

      if disable_db_ssl do
        config :lightning, Lightning.Repo, ssl: false
      else
        ssl_opts = [verify: :verify_none]

        config :lightning, Lightning.Repo, ssl_opts: ssl_opts, ssl: true
      end

      # The secret key base is used to sign/encrypt cookies and other secrets.
      # A default value is used in config/dev.exs and config/test.exs but you
      # want to use a different value for prod and you most likely don't want
      # to check this value into version control, so we use an environment
      # variable instead.
      secret_key_base =
        env!("SECRET_KEY_BASE", :string, nil) ||
          raise """
          environment variable SECRET_KEY_BASE is missing.
          You can generate one by calling: mix phx.gen.secret
          """

      listen_address =
        env!(
          "LISTEN_ADDRESS",
          fn address ->
            address
            |> String.split(".")
            |> Enum.map(&String.to_integer/1)
            |> List.to_tuple()
          end,
          {127, 0, 0, 1}
        )

      origins =
        env!(
          "ORIGINS",
          fn str ->
            case str do
              nil -> true
              _ -> String.split(str, ",")
            end
          end,
          nil
        )

      url_scheme = env!("URL_SCHEME", :string, "https")

      retry_timeout_ms = Lightning.Config.webhook_retry(:timeout_ms)

      idle_default_ms = max(60_000, retry_timeout_ms + 15_000)

      idle_timeout =
        env!(
          "IDLE_TIMEOUT",
          fn str ->
            case Integer.parse(str) do
              {val, _} -> val * 1_000
              :error -> idle_default_ms
            end
          end,
          idle_default_ms
        )

      config :lightning, LightningWeb.Endpoint,
        url: [host: host, port: url_port, scheme: url_scheme],
        secret_key_base: secret_key_base,
        check_origin: origins,
        http: [
          ip: listen_address,
          port: port,
          compress: true,
          protocol_options: [
            # Note that if a request is more than 10x the max dataclip size, we cut
            # the connection immediately to prevent memory issues via the
            # :max_skip_body_length setting.
            max_skip_body_length:
              Application.get_env(
                :lightning,
                :max_dataclip_size_bytes,
                10_000_000
              ) * 10,
            idle_timeout: idle_timeout
          ]
        ],
        server: true
    end

    if config_env() == :test do
      # When running tests, set the number of database connections to the number
      # of cores available.
      schedulers = :erlang.system_info(:schedulers_online)

      config :lightning, Lightning.Repo,
        pool_size: Enum.max([schedulers + 8, schedulers * 2])

      config :ex_unit,
        assert_receive_timeout: env!("ASSERT_RECEIVE_TIMEOUT", :integer, 1000),
        timeout: env!("EX_UNIT_TIMEOUT", :integer, 60_000)
    end

    config :sentry,
      dsn: env!("SENTRY_DSN", :string, nil),
      filter: Lightning.SentryEventFilter,
      environment_name: env!("SENTRY_ENVIRONMENT", :string, config_env()),
      tags: %{host: host},
      release: release[:label],
      enable_source_code_context: true,
      root_source_code_path: File.cwd!()

    config :lightning, Lightning.PromEx,
      disabled: not env!("PROMEX_ENABLED", &Utils.ensure_boolean/1, false),
      manual_metrics_start_delay: :no_delay,
      drop_metrics_groups: [],
      expensive_metrics_enabled:
        env!("PROMEX_EXPENSIVE_METRICS_ENABLED", &Utils.ensure_boolean/1, false),
      grafana: [
        host: env!("PROMEX_GRAFANA_HOST", :string, ""),
        username: env!("PROMEX_GRAFANA_USER", :string, ""),
        password: env!("PROMEX_GRAFANA_PASSWORD", :string, ""),
        upload_dashboards_on_start:
          env!(
            "PROMEX_UPLOAD_GRAFANA_DASHBOARDS_ON_START",
            &Utils.ensure_boolean/1,
            false
          )
      ],
      metrics_server: :disabled,
      datasource_id: env!("PROMEX_DATASOURCE_ID", :string, ""),
      metrics_endpoint_authorization_required:
        env!(
          "PROMEX_METRICS_ENDPOINT_AUTHORIZATION_REQUIRED",
          &Utils.ensure_boolean/1,
          true
        ),
      metrics_endpoint_token:
        env!(
          "PROMEX_METRICS_ENDPOINT_TOKEN",
          :string,
          :crypto.strong_rand_bytes(100)
        ),
      metrics_endpoint_scheme: env!("PROMEX_ENDPOINT_SCHEME", :string, "https")

    config :lightning, :metrics,
      stalled_run_threshold_seconds:
        env!("METRICS_STALLED_RUN_THRESHOLD_SECONDS", :integer, 3600),
      run_performance_age_seconds:
        env!("METRICS_RUN_PERFORMANCE_AGE_SECONDS", :integer, 300),
      run_queue_metrics_period_seconds:
        env!("METRICS_RUN_QUEUE_METRICS_PERIOD_SECONDS", :integer, 5),
      unclaimed_run_threshold_seconds:
        env!("METRICS_UNCLAIMED_RUN_THRESHOLD_SECONDS", :integer, 10)

    config :lightning,
           :per_workflow_claim_limit,
           env!("PER_WORKFLOW_CLAIM_LIMIT", :integer, 50)
           |> then(fn limit ->
             if limit <= 0 do
               raise """
               PER_WORKFLOW_CLAIM_LIMIT must be a positive integer.
               """
             end

             limit
           end)

    config :lightning,
           :claim_work_mem,
           env!("CLAIM_WORK_MEM", :string, nil)
           |> then(fn
             nil ->
               nil

             "" ->
               nil

             value ->
               unless Regex.match?(~r/^\d+(kB|MB|GB|TB)$/i, value) do
                 raise """
                 Invalid CLAIM_WORK_MEM value: #{inspect(value)}

                 Must be a valid PostgreSQL memory value (e.g., "32MB", "1GB", "256kB").
                 """
               end

               value
           end)

    config :lightning, :usage_tracking,
      cleartext_uuids_enabled:
        env!("USAGE_TRACKING_UUIDS", :string, nil) == "cleartext",
      enabled: env!("USAGE_TRACKING_ENABLED", &Utils.ensure_boolean/1, true),
      host: env!("USAGE_TRACKER_HOST", :string, "https://impact.openfn.org"),
      resubmission_batch_size:
        env!("USAGE_TRACKING_RESUBMISSION_BATCH_SIZE", :integer, 10),
      daily_batch_size: env!("USAGE_TRACKING_DAILY_BATCH_SIZE", :integer, 10),
      run_chunk_size: env!("USAGE_TRACKING_RUN_CHUNK_SIZE", :integer, 100)

    config :lightning, :kafka_triggers,
      alternate_storage_enabled:
        env!(
          "KAFKA_ALTERNATE_STORAGE_ENABLED",
          &Utils.ensure_boolean/1,
          false
        )
        |> tap(fn enabled ->
          if enabled do
            touch_result =
              env!("KAFKA_ALTERNATE_STORAGE_FILE_PATH", :string, nil)
              |> to_string()
              |> then(fn path ->
                if File.exists?(path) do
                  path
                  |> Path.join(".lightning_storage_check")
                  |> File.touch()
                else
                  :error
                end
              end)

            unless touch_result == :ok do
              raise """
              KAFKA_ALTERNATE_STORAGE_ENABLED is set to yes/true.

              KAFKA_ALTERNATE_STORAGE_FILE_PATH must be a writable directory.
              """
            end
          end
        end),
      alternate_storage_file_path:
        env!("KAFKA_ALTERNATE_STORAGE_FILE_PATH", :string, nil),
      duplicate_tracking_retention_seconds:
        env!("KAFKA_DUPLICATE_TRACKING_RETENTION_SECONDS", :integer, 3600),
      enabled: env!("KAFKA_TRIGGERS_ENABLED", &Utils.ensure_boolean/1, false),
      notification_embargo_seconds:
        env!("KAFKA_NOTIFICATION_EMBARGO_SECONDS", :integer, 3600),
      number_of_consumers: env!("KAFKA_NUMBER_OF_CONSUMERS", :integer, 1),
      number_of_messages_per_second:
        env!("KAFKA_NUMBER_OF_MESSAGES_PER_SECOND", :float, 1),
      number_of_processors: env!("KAFKA_NUMBER_OF_PROCESSORS", :integer, 1)

    config :lightning, :ui_metrics_tracking,
      enabled: env!("UI_METRICS_ENABLED", &Utils.ensure_boolean/1, false)

    config :lightning,
           :broadcast_work_available,
           env!("BROADCAST_WORK_AVAILABLE", &Utils.ensure_boolean/1, true)

    config :lightning, Lightning.Scrubber,
      max_credential_sensitive_values:
        env!("MAX_CREDENTIAL_SENSITIVE_VALUES", :integer, 50)

    config :lightning, :book_demo_banner,
      enabled: false,
      calendly_url: nil,
      openfn_workflow_url: nil

    config :lightning, :distributed_erlang,
      node_discovery_via_postgres_enabled:
        env!(
          "ERLANG_NODE_DISCOVERY_VIA_POSTGRES_ENABLED",
          &Utils.ensure_boolean/1,
          false
        ),
      node_discovery_via_postgres_channel_name:
        env!(
          "ERLANG_NODE_DISCOVERY_VIA_POSTGRES_CHANNEL_NAME",
          :string,
          "lightning-cluster"
        )

    # ==============================================================================

    setup_storage()

    config :lightning, :env, config_env()

    # Commenting this out because the React modules aren't being used in prod
    # Utils.get_env([:esbuild, :default, :args]) returns nil in prod
    # We should have uncomment it when we have a proper fix
    # entry_points = React.get_entry_points(:lightning)

    # config :esbuild, :default,
    #   args: Utils.get_env([:esbuild, :default, :args]) ++ entry_points

    :ok
  end

  defp setup_storage do
    config :lightning, Lightning.Storage,
      path: env!("STORAGE_PATH", :string, ".")

    env!("STORAGE_BACKEND", :string, "local")
    |> case do
      "gcs" ->
        config :lightning, Lightning.Storage,
          backend: Lightning.Storage.GCS,
          bucket:
            env!("GCS_BUCKET", :string, nil) ||
              raise("GCS_BUCKET is not set, but STORAGE_BACKEND is set to gcs")

        google_required()

      "local" ->
        config :lightning, Lightning.Storage, backend: Lightning.Storage.Local

      unknown ->
        raise """
        Unknown storage backend: #{unknown}

        Currently supported backends are:

        - gcs
        - local (default)
        """
    end
  end

  # Not really happy about having to put this here, but for some reason
  # dialyzer thinks that when :error can be matched then {:error, _} can't be.
  @dialyzer {:no_match, google_required: 0}
  defp google_required do
    with value when is_binary(value) <-
           env!(
             "GOOGLE_APPLICATION_CREDENTIALS_JSON",
             :string,
             {:error,
              "GOOGLE_APPLICATION_CREDENTIALS_JSON is not set, this is required when using Google Cloud services."}
           ),
         {:ok, decoded} <- Base.decode64(value),
         {:ok, credentials} <- Jason.decode(decoded) do
      config :lightning, Lightning.Google,
        credentials: credentials,
        required: true
    else
      {:error, %Jason.DecodeError{} = error} ->
        raise """
        Could not decode GOOGLE_APPLICATION_CREDENTIALS_JSON: #{Jason.DecodeError.message(error)}
        """

      {:error, message} ->
        raise message

      :error ->
        raise "Could not decode GOOGLE_APPLICATION_CREDENTIALS_JSON"
    end
  end

  defp github_config do
    decoded_cert =
      env!(
        "GITHUB_CERT",
        fn encoded ->
          encoded
          |> Base.decode64()
          |> case do
            {:ok, decoded} ->
              decoded

            :error ->
              raise """
              Could not decode GITHUB_CERT.

              Ensure you have encoded the certificate as a base64 string.

              For example:

                  cat private-key.pem | base64 -w 0
              """
          end
        end,
        Utils.get_env([:lightning, :github_app, :cert])
      )

    github_app_id =
      env!(
        "GITHUB_APP_ID",
        :string,
        Utils.get_env([:lightning, :github_app, :app_id])
      )

    github_app_name =
      env!(
        "GITHUB_APP_NAME",
        :string,
        Utils.get_env([:lightning, :github_app, :app_name])
      )

    github_app_client_id =
      env!(
        "GITHUB_APP_CLIENT_ID",
        :string,
        Utils.get_env([:lightning, :github_app, :client_id])
      )

    github_app_client_secret =
      env!(
        "GITHUB_APP_CLIENT_SECRET",
        :string,
        Utils.get_env([:lightning, :github_app, :client_secret])
      )

    [
      cert: decoded_cert,
      app_id: github_app_id,
      app_name: github_app_name,
      client_id: github_app_client_id,
      client_secret: github_app_client_secret
    ]
  end

  defp setup_webhook_retry do
    webhook_retry_config =
      [
        max_attempts: env!("WEBHOOK_RETRY_MAX_ATTEMPTS", :integer, nil),
        initial_delay_ms: env!("WEBHOOK_RETRY_INITIAL_DELAY_MS", :integer, nil),
        max_delay_ms: env!("WEBHOOK_RETRY_MAX_DELAY_MS", :integer, nil),
        backoff_factor: env!("WEBHOOK_RETRY_BACKOFF_FACTOR", :float, nil),
        timeout_ms: env!("WEBHOOK_RETRY_TIMEOUT_MS", :integer, nil),
        jitter: env!("WEBHOOK_RETRY_JITTER", &Utils.ensure_boolean/1, nil)
      ]
      |> Enum.reject(fn {_, value} -> is_nil(value) end)

    if webhook_retry_config != [] do
      config :lightning, :webhook_retry, webhook_retry_config
    end
  end

  defp release_info do
    [
      label: "v#{Application.spec(:lightning, :vsn)}",
      image_tag: env!("IMAGE_TAG", :string, nil),
      branch: env!("BRANCH", :string, nil),
      commit: env!("COMMIT", :string, nil)
    ]
  end

  defp get_env(app) do
    Process.get({Config, :config})
    |> Keyword.get(app)
  end

  @doc """
  Retrieve a value nested in the application environment.

  It first searches the current process's config dictionary, then falls back to
  the application environment.
  """
  def get_env(app, keys) do
    case get_env(app) |> get_in(keys) do
      nil -> Application.get_all_env(app) |> get_in(keys)
      value -> value
    end
  end

  defp validate_rsa_key!(pem) when is_binary(pem) do
    case parse_rsa_key(pem) do
      :ok -> :ok
      {:error, message} -> raise message
    end
  end

  defp parse_rsa_key(pem) do
    case JOSE.JWK.from_pem(pem) do
      %JOSE.JWK{kty: {:jose_jwk_kty_rsa, _}} ->
        :ok

      %JOSE.JWK{kty: {kty_module, _}} ->
        key_type =
          kty_module |> to_string() |> String.replace("jose_jwk_kty_", "")

        {:error,
         worker_key_error(
           "has wrong key type: #{key_type}\n\nLightning requires an RSA key for RS256 signing, but the configured key is #{key_type}."
         )}

      _ ->
        {:error, worker_key_error("could not be parsed as a valid key.")}
    end
  rescue
    e ->
      {:error, worker_key_error("could not be parsed: #{Exception.message(e)}")}
  end

  defp worker_key_error(reason) do
    """
    WORKER_RUNS_PRIVATE_KEY #{reason}

    You can generate new worker keys using: mix lightning.gen_worker_keys
    """
  end
end
