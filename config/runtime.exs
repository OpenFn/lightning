import Config
import Dotenvy

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# Use Vapor to load configuration from environment variables, files, etc.
# Then merge the resulting configuration into the Application config.

source!([
  ".env",
  ".#{config_env()}.env",
  ".#{config_env()}.override.env",
  System.get_env()
])

# Start the phoenix server if environment is set and running in a release
if System.get_env("PHX_SERVER") && System.get_env("RELEASE_NAME") do
  config :lightning, LightningWeb.Endpoint, server: true
end

if is_resettable_demo = System.get_env("IS_RESETTABLE_DEMO") do
  config :lightning,
         :is_resettable_demo,
         is_resettable_demo == "yes"
end

if default_retention_period = System.get_env("DEFAULT_RETENTION_PERIOD") do
  config :lightning,
         :default_retention_period,
         String.to_integer(default_retention_period)
end

decoded_cert =
  System.get_env("GITHUB_CERT")
  |> case do
    nil ->
      nil

    str ->
      case Base.decode64(str) do
        :error ->
          raise """
          Could not decode GITHUB_CERT.

          Ensure you have encoded the certificate as a base64 string.

          For example:

              cat private-key.pem | base64 -w 0
          """

        {:ok, decoded} ->
          decoded
      end
  end ||
    Application.get_env(:lightning, :github_app, [])
    |> Keyword.get(:cert, nil)

github_app_id =
  System.get_env("GITHUB_APP_ID") ||
    Application.get_env(:lightning, :github_app, [])
    |> Keyword.get(:app_id, nil)

github_app_name =
  System.get_env("GITHUB_APP_NAME") ||
    Application.get_env(:lightning, :github_app, [])
    |> Keyword.get(:app_name, nil)

github_app_client_id =
  System.get_env("GITHUB_APP_CLIENT_ID") ||
    Application.get_env(:lightning, :github_app, [])
    |> Keyword.get(:client_id, nil)

github_app_client_secret =
  System.get_env("GITHUB_APP_CLIENT_SECRET") ||
    Application.get_env(:lightning, :github_app, [])
    |> Keyword.get(:client_secret, nil)

config :lightning, :github_app,
  cert: decoded_cert,
  app_id: github_app_id,
  app_name: github_app_name,
  client_id: github_app_client_id,
  client_secret: github_app_client_secret

if start_rtm = System.get_env("RTM") do
  unless start_rtm in ["true", "false"] do
    raise """
    Expected `RTM` value to either be "true" or "false".
    """
  end

  config :lightning, Lightning.Runtime.RuntimeManager,
    start: start_rtm |> String.to_existing_atom()
end

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
      Application.get_env(:lightning, :workers, []) |> Keyword.get(:private_key)
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
      Application.get_env(:lightning, :workers, [])
      |> Keyword.get(:worker_secret)
    )
    |> tap(fn v ->
      unless v do
        raise "No worker secret found, please set WORKER_SECRET"
      end
    end)

image_tag = System.get_env("IMAGE_TAG")
branch = System.get_env("BRANCH")
commit = System.get_env("COMMIT")

config :lightning, :image_info,
  image_tag: image_tag,
  branch: branch,
  commit: commit

config :lightning, :email_addresses,
  admin: System.get_env("EMAIL_ADMIN", "support@openfn.org")

config :lightning, :adaptor_service,
  adaptors_path: System.get_env("ADAPTORS_PATH", "./priv/openfn")

config :lightning, :oauth_clients,
  google: [
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
  ],
  salesforce: [
    client_id: System.get_env("SALESFORCE_CLIENT_ID"),
    client_secret: System.get_env("SALESFORCE_CLIENT_SECRET")
  ]

config :lightning,
  schemas_path:
    System.get_env("SCHEMAS_PATH") ||
      Application.get_env(:lightning, :schemas_path) || "./priv"

config :lightning,
       :purge_deleted_after_days,
       System.get_env("PURGE_DELETED_AFTER_DAYS", "7")
       |> String.to_integer()

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
  {"1 2 * * *", Lightning.Projects, args: %{"type" => "data_retention"}}
]

usage_tracking_daily_batch_size =
  "USAGE_TRACKING_DAILY_BATCH_SIZE"
  |> System.get_env("10")
  |> String.to_integer()

usage_tracking_cron = [
  {
    "30 1 * * *",
    Lightning.UsageTracking.DayWorker,
    args: %{"batch_size" => usage_tracking_daily_batch_size}
  }
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

all_cron = base_cron ++ usage_tracking_cron ++ cleanup_cron

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
if System.get_env("PLAUSIBLE_SRC"),
  do:
    config(
      :lightning,
      :plausible,
      src: System.get_env("PLAUSIBLE_SRC"),
      "data-domain": System.get_env("PLAUSIBLE_DATA_DOMAIN")
    )

config :lightning,
       :max_run_duration_seconds,
       System.get_env("WORKER_MAX_RUN_DURATION_SECONDS", "60")
       |> String.to_integer()

config :lightning,
       :max_dataclip_size_bytes,
       System.get_env("MAX_DATACLIP_SIZE_MB", "10")
       |> String.to_integer()
       |> Kernel.*(1_000_000)

config :lightning,
       :queue_result_retention_period,
       System.get_env("QUEUE_RESULT_RETENTION_PERIOD_SECONDS", "60")
       |> String.to_integer()

config :lightning,
       :init_project_for_new_user,
       System.get_env("INIT_PROJECT_FOR_NEW_USER", "false")
       |> String.to_existing_atom()

# To actually send emails you need to configure the mailer to use a real
# adapter. You may configure the swoosh api client of your choice. We
# automatically configure Mailgun if an API key has been provided. See
# https://hexdocs.pm/swoosh/Swoosh.html#module-installation for more details.
if System.get_env("MAILGUN_API_KEY") do
  config :lightning, Lightning.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: System.get_env("MAILGUN_API_KEY"),
    domain: System.get_env("MAILGUN_DOMAIN")
end

url_port = String.to_integer(System.get_env("URL_PORT", "443"))
url_scheme = System.get_env("URL_SCHEME", "https")

# Use the `PRIMARY_ENCRYPTION_KEY` env variable if available, else fall back
# to defaults.
# Defaults are set for `dev` and `test` modes.
config :lightning, Lightning.Vault,
  primary_encryption_key:
    System.get_env("PRIMARY_ENCRYPTION_KEY") ||
      Application.get_env(:lightning, Lightning.Vault, [])
      |> Keyword.get(:primary_encryption_key, nil)

if log_level = System.get_env("LOG_LEVEL") do
  allowed_log_levels =
    ~w[emergency alert critical error warning warn notice info debug]

  if log_level in allowed_log_levels do
    config :logger, level: log_level |> String.to_atom()
  else
    raise """
    Invalid LOG_LEVEL, must be on of #{allowed_log_levels |> Enum.join(", ")}
    """
  end
end

database_url = System.get_env("DATABASE_URL")

config :lightning, Lightning.Repo,
  url: database_url,
  pool_size: env!("DATABASE_POOL_SIZE", :integer, 10),
  timeout: env!("DATABASE_TIMEOUT", :integer, 15_000),
  queue_target: env!("DATABASE_QUEUE_TARGET", :integer, 50),
  queue_interval: env!("DATABASE_QUEUE_INTERVAL", :integer, 1000)

if config_env() == :prod do
  unless database_url do
    raise """
    environment variable DATABASE_URL is missing.
    For example: ecto://USER:PASS@HOST/DATABASE
    """
  end

  maybe_ipv6 = if System.get_env("ECTO_IPV6"), do: [:inet6], else: []
  enforce_repo_ssl = System.get_env("DISABLE_DB_SSL") != "true"

  config :lightning, Lightning.Repo,
    ssl: enforce_repo_ssl,
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
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("URL_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT", "4000"))

  listen_address =
    System.get_env("LISTEN_ADDRESS", "127.0.0.1")
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()

  origins =
    case System.get_env("ORIGINS") do
      nil -> true
      str -> String.split(str, ",")
    end

  config :lightning, LightningWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    http: [
      ip: listen_address,
      port: port,
      compress: true
    ],
    secret_key_base: secret_key_base,
    check_origin: origins,
    http: [
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
    assert_receive_timeout:
      System.get_env("ASSERT_RECEIVE_TIMEOUT", "600") |> String.to_integer()
end

release =
  case image_tag do
    nil -> "mix-v#{Application.spec(:lightning, :vsn)}"
    "edge" -> commit
    _other -> image_tag
  end

config :sentry,
  filter: Lightning.SentryEventFilter,
  environment_name: config_env(),
  tags: %{
    host: Application.get_env(:lightning, LightningWeb.Endpoint)[:url][:host]
  },
  # If you've booted up with a SENTRY_DSN environment variable, use Sentry!
  included_environments:
    if(System.get_env("SENTRY_DSN"), do: [config_env()], else: []),
  release: release,
  enable_source_code_context: true,
  root_source_code_path: File.cwd!()

config :lightning, Lightning.PromEx,
  disabled: System.get_env("PROMEX_ENABLED") != "true",
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: [
    host: System.get_env("PROMEX_GRAFANA_HOST") || "",
    username: System.get_env("PROMEX_GRAFANA_USER") || "",
    password: System.get_env("PROMEX_GRAFANA_PASSWORD") || "",
    upload_dashboards_on_start:
      System.get_env("PROMEX_UPLOAD_GRAFANA_DASHBOARDS_ON_START") == "true"
  ],
  metrics_server: :disabled,
  datasource_id: System.get_env("PROMEX_DATASOURCE_ID") || "",
  metrics_endpoint_authorization_required:
    System.get_env("PROMEX_METRICS_ENDPOINT_AUTHORIZATION_REQUIRED") != "no",
  metrics_endpoint_token:
    System.get_env("PROMEX_METRICS_ENDPOINT_TOKEN") ||
      :crypto.strong_rand_bytes(100),
  metrics_endpoint_scheme: System.get_env("PROMEX_ENDPOINT_SCHEME") || "https"

config :lightning, :metrics,
  stalled_run_threshold_seconds:
    String.to_integer(
      System.get_env("METRICS_STALLED_RUN_THRESHOLD_SECONDS", "3600")
    ),
  run_performance_age_seconds:
    String.to_integer(
      System.get_env("METRICS_RUN_PERFORMANCE_AGE_SECONDS", "300")
    ),
  run_queue_metrics_period_seconds:
    String.to_integer(
      System.get_env("METRICS_RUN_QUEUE_METRICS_PERIOD_SECONDS", "5")
    )

config :lightning, :usage_tracking,
  cleartext_uuids_enabled: System.get_env("USAGE_TRACKING_UUIDS") == "cleartext",
  enabled: System.get_env("USAGE_TRACKING_ENABLED") != "false",
  host: System.get_env("USAGE_TRACKER_HOST", "https://impact.openfn.org")
