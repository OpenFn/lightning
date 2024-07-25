alias Lightning.Config.Utils
import Config
import Dotenvy

require Logger

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# We use dotenvy to load environment variables from .env files.
# The order of precedence (last winning) is, `.env`, `<config_env>.env`,
# `<config_env>.override.env`, and then system environment variables.

# See the dotenvy cheatsheet for more information:
# https://hexdocs.pm/dotenvy/cheatsheet.html

# NOTE: Any calls to `System.get_env()` will return the value from the
# environment, which does not include the values from the `.env` files.

source!([
  ".env",
  ".#{config_env()}.env",
  ".#{config_env()}.override.env",
  System.get_env()
])

# Start the phoenix server if environment is set and running in a release
if env!("PHX_SERVER", :boolean, false) && env!("RELEASE_NAME", :boolean, false) do
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

github_config = [
  cert: decoded_cert,
  app_id: github_app_id,
  app_name: github_app_name,
  client_id: github_app_client_id,
  client_secret: github_app_client_secret
]

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
  openai_api_key: env!("OPENAI_API_KEY", :string, nil)

config :lightning, Lightning.Runtime.RuntimeManager,
  start:
    env!(
      "RTM",
      &Utils.ensure_boolean/1,
      Utils.get_env([:lightning, Lightning.Runtime.RuntimeManager, :start])
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
    end),
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

release = [
  label: "v#{Application.spec(:lightning, :vsn)}",
  image_tag: env!("IMAGE_TAG", :string, nil),
  branch: env!("BRANCH", :string, nil),
  commit: env!("COMMIT", :string, nil)
]

config :lightning, :release, release

config :lightning, :emails,
  admin_email: env!("EMAIL_ADMIN", :string, "support@openfn.org"),
  sender_name: env!("EMAIL_SENDER_NAME", :string, "OpenFn")

config :lightning, :adaptor_service,
  adaptors_path: env!("ADAPTORS_PATH", :string, "./priv/openfn")

config :lightning, :oauth_clients,
  google: [
    client_id: env!("GOOGLE_CLIENT_ID", :string, nil),
    client_secret: env!("GOOGLE_CLIENT_SECRET", :string, nil)
  ],
  salesforce: [
    client_id: env!("SALESFORCE_CLIENT_ID", :string, nil),
    client_secret: env!("SALESFORCE_CLIENT_SECRET", :string, nil)
  ]

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
  {"1 2 * * *", Lightning.Projects, args: %{"type" => "data_retention"}},
  {"*/10 * * * *", Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker}
]

cleanup_cron =
  if Application.get_env(:lightning, :purge_deleted_after_days) > 0,
    do: [
      {"2 2 * * *", Lightning.Accounts, args: %{"type" => "purge_deleted"}},
      {"3 2 * * *", Lightning.Credentials, args: %{"type" => "purge_deleted"}},
      {"4 2 * * *", Lightning.Projects, args: %{"type" => "purge_deleted"}},
      {"5 2 * * *", Lightning.WebhookAuthMethods,
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
    background: 1
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
       env!("QUEUE_RESULT_RETENTION_PERIOD_SECONDS", :integer, 60)

config :lightning,
       :allow_signup,
       env!("ALLOW_SIGNUP", &Utils.ensure_boolean/1, false)

config :lightning,
       :init_project_for_new_user,
       env!("INIT_PROJECT_FOR_NEW_USER", &Utils.ensure_boolean/1, false)

# To actually send emails you need to configure the mailer to use a real
# adapter. You may configure the swoosh api client of your choice. We
# automatically configure Mailgun if an API key has been provided. See
# https://hexdocs.pm/swoosh/Swoosh.html#module-installation for more details.
if api_key = env!("MAILGUN_API_KEY", :string, nil) do
  config :lightning, Lightning.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: api_key,
    domain: env!("MAILGUN_DOMAIN", :string)
end

# Use the `PRIMARY_ENCRYPTION_KEY` env variable if available, else fall back
# to defaults.
# Defaults are set for `dev` and `test` modes.
config :lightning, Lightning.Vault,
  primary_encryption_key:
    env!(
      "PRIMARY_ENCRYPTION_KEY",
      :string,
      Utils.get_env([:lightning, Lightning.Vault, :primary_encryption_key], nil)
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
port = env!("PORT", :integer, 4000)
url_port = env!("URL_PORT", :integer, 443)

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
    if env!("ECTO_IPV6", &Utils.ensure_boolean/1, false), do: [:inet6], else: []

  disable_db_ssl = env!("DISABLE_DB_SSL", &Utils.ensure_boolean/1, false)

  config :lightning, Lightning.Repo,
    ssl: not disable_db_ssl,
    # TODO: determine why we see this certs verification warn for the repo conn
    # ssl_opts: [log_level: :error],
    url: database_url,
    socket_options: maybe_ipv6

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

  config :lightning, LightningWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    secret_key_base: secret_key_base,
    check_origin: origins,
    http: [
      ip: listen_address,
      port: port,
      compress: true,
      protocol_options: [
        max_frame_size:
          Application.get_env(:lightning, :max_dataclip_size_bytes, 10_000_000),
        # Note that if a request is more than 10x the max dataclip size, we cut
        # the connection immediately to prevent memory issues via the
        # :max_skip_body_length setting.
        max_skip_body_length:
          Application.get_env(:lightning, :max_dataclip_size_bytes, 10_000_000) *
            10
      ]
    ],
    server: true

  # ## Using releases
  #
  # If you are doing OTP releases, you need to instruct Phoenix
  # to start each relevant endpoint:
  #
  # config :lightning, LightningWeb.Endpoint, server: true
  #
  # Then you can assemble a release by calling `mix release`.
  # See `mix help release` for more information.
end

if config_env() == :test do
  # When running tests, set the number of database connections to the number
  # of cores available.
  schedulers = :erlang.system_info(:schedulers_online)

  config :lightning, Lightning.Repo,
    pool_size: Enum.max([schedulers + 8, schedulers * 2])

  config :ex_unit,
    assert_receive_timeout: env!("ASSERT_RECEIVE_TIMEOUT", :integer, 600)
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
    env!("METRICS_RUN_QUEUE_METRICS_PERIOD_SECONDS", :integer, 5)

config :lightning, :usage_tracking,
  cleartext_uuids_enabled:
    env!("USAGE_TRACKING_UUIDS", :string, nil) == "cleartext",
  enabled: env!("USAGE_TRACKING_ENABLED", &Utils.ensure_boolean/1, true),
  host: env!("USAGE_TRACKER_HOST", :string, "https://impact.openfn.org"),
  resubmission_batch_size:
    env!("USAGE_TRACKING_RESUBMISSION_BATCH_SIZE", :integer, 10),
  daily_batch_size: env!("USAGE_TRACKING_DAILY_BATCH_SIZE", :integer, 10)

config :lightning, :kafka_triggers,
  duplicate_tracking_retention_seconds:
    env!("KAFKA_DUPLICATE_TRACKING_RETENTION_SECONDS", :integer, 3600),
  enabled: env!("KAFKA_TRIGGERS_ENABLED", &Utils.ensure_boolean/1, false),
  next_message_candidate_set_delay_milliseconds:
    env!(
      "KAFKA_NEXT_MESSAGE_CANDIDATE_SET_DELAY_MILLISECONDS",
      :integer,
      250
    ),
  no_message_candidate_set_delay_milliseconds:
    env!(
      "KAFKA_NO_MESSAGE_CANDIDATE_SET_DELAY_MILLISECONDS",
      :integer,
      10000
    ),
  number_of_consumers: env!("KAFKA_NUMBER_OF_CONSUMERS", :integer, 1),
  number_of_message_candidate_set_workers:
    env!("KAFKA_NUMBER_OF_MESSAGE_CANDIDATE_SET_WORKERS", :integer, 1),
  number_of_messages_per_second:
    env!("KAFKA_NUMBER_OF_MESSAGES_PER_SECOND", :float, 1),
  number_of_processors: env!("KAFKA_NUMBER_OF_PROCESSORS", :integer, 1)

# ==============================================================================
