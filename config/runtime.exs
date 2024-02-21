import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# Use Vapor to load configuration from environment variables, files, etc.
# Then merge the resulting configuration into the Application config.
env_config = Vapor.load!(Lightning.Env)

env_config
|> Enum.each(fn {k, v} -> config(:lightning, k, v |> Enum.into([])) end)

# Start the phoenix server if environment is set and running in a release
if System.get_env("PHX_SERVER") && System.get_env("RELEASE_NAME") do
  config :lightning, LightningWeb.Endpoint, server: true
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
    |> Keyword.get(:app_id, nil)

config :lightning, :github_app,
  cert: decoded_cert,
  app_id: github_app_id,
  app_name: github_app_name

if System.get_env("RTM") == "false" do
  config :lightning, Lightning.Runtime.RuntimeManager, start: false
end

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

base_oban_cron = [
  {"* * * * *", Lightning.Workflows.Scheduler},
  {"* * * * *", ObanPruner},
  {"0 10 * * *", Lightning.DigestEmailWorker,
   args: %{"type" => "daily_project_digest"}},
  {"0 10 * * 1", Lightning.DigestEmailWorker,
   args: %{"type" => "weekly_project_digest"}},
  {"0 10 1 * *", Lightning.DigestEmailWorker,
   args: %{"type" => "monthly_project_digest"}}
]

purge_cron =
  if System.get_env("PURGE_DELETED_AFTER_DAYS") != "0",
    do: [
      {"0 2 * * *", Lightning.WebhookAuthMethods,
       args: %{"type" => "purge_deleted"}},
      {"0 2 * * *", Lightning.Credentials, args: %{"type" => "purge_deleted"}},
      {"*/5 * * * *", Lightning.Janitor},
      {"0 2 * * *", Lightning.Accounts, args: %{"type" => "purge_deleted"}},
      {"0 2 * * *", Lightning.Projects, args: %{"type" => "purge_deleted"}}
    ],
    else: []

usage_tracking_cron = [{"0 2 * * *", Lightning.UsageTracking.Worker}]

all_cron = base_oban_cron ++ purge_cron ++ usage_tracking_cron

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
       :purge_deleted_after_days,
       System.get_env("PURGE_DELETED_AFTER_DAYS", "7")
       |> String.to_integer()

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
       |> String.to_atom()

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

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6"), do: [:inet6], else: []
  enforce_repo_ssl = System.get_env("DISABLE_DB_SSL") != "true"

  config :lightning, Lightning.Repo,
    ssl: enforce_repo_ssl,
    # TODO: determine why we see this certs verification warn for the repo conn
    # ssl_opts: [log_level: :error],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
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
  port = String.to_integer(System.get_env("PORT") || "4000")

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
    )

config :lightning, :usage_tracking,
  cleartext_uuids_enabled: System.get_env("USAGE_TRACKING_UUIDS") == "cleartext",
  enabled: System.get_env("USAGE_TRACKING_ENABLED") != "false",
  host: System.get_env("USAGE_TRACKER_HOST", "https://impact.openfn.org")
