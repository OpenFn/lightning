import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Start the phoenix server if environment is set and running in a release
if System.get_env("PHX_SERVER") && System.get_env("RELEASE_NAME") do
  config :lightning, LightningWeb.Endpoint, server: true
end

image = System.get_env("IMAGE_TAG")
branch = System.get_env("BRANCH")
commit = System.get_env("COMMIT")
vsn = "v#{elem(:application.get_key(:lightning, :vsn), 1)}"

{version_display, version_message, version_type} =
  cond do
    # If running in docker on edge, display commit SHA.
    image == "edge" ->
      {commit,
       "Lightning #{image} in Docker (built from #{commit} on #{branch})", :edge}

    # If running in docker and tag matches :vsn, display :vsn and standard message.
    image == vsn ->
      {vsn, "Lightning #{vsn} in Docker (built from #{commit} on #{branch})",
       :release}

    # If running in docker and tag doesn't match :vsn, display :vsn and warning.
    image != nil and image != vsn ->
      {commit,
       "Lightning #{vsn} (tagged as #{image}, built from #{commit} on #{branch})",
       :warn}

    true ->
      {vsn, "Lightning #{vsn}", :no_docker}
  end

config :lightning, :version,
  display: version_display,
  message: version_message,
  type: version_type

config :lightning, :email_addresses,
  admin: System.get_env("EMAIL_ADMIN", "admin@openfn.org")

config :lightning, :adaptor_service,
  adaptors_path: System.get_env("ADAPTORS_PATH", "./priv/openfn")

config :lightning, :oauth_clients,
  google: [
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
  ]

config :lightning,
  schemas_path:
    System.get_env("SCHEMAS_PATH") ||
      Application.get_env(:lightning, :schemas_path) || "./priv"

config :lightning, Oban,
  repo: Lightning.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Lightning.Jobs.Scheduler},
       {"* * * * *", ObanPruner},
       {"0 2 * * *", Lightning.Accounts, args: %{"type" => "purge_deleted"}},
       {"0 10 * * *", Lightning.DigestEmailWorker,
        args: %{"type" => "daily_project_digest"}},
       {"0 10 * * MON", Lightning.DigestEmailWorker,
        args: %{"type" => "weekly_project_digest"}},
       {"0 10 1 * *", Lightning.DigestEmailWorker,
        args: %{"type" => "monthly_project_digest"}}
     ]}
  ],
  shutdown_grace_period:
    System.get_env("MAX_RUN_DURATION", "60000")
    |> String.to_integer(),
  dispatch_cooldown: 100,
  queues: [
    scheduler: 1,
    workflow_failures: 1,
    background: 1,
    runs:
      System.get_env(
        "GLOBAL_RUNS_CONCURRENCY",
        :erlang.system_info(:logical_processors_available) |> to_string()
      )
      |> String.to_integer()
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
       :max_run_duration,
       System.get_env("MAX_RUN_DURATION", "60000")
       |> String.to_integer()

config :lightning,
       :queue_result_retention_period,
       System.get_env("QUEUE_RESULT_RETENTION_PERIOD", "60")
       |> String.to_integer()

config :lightning,
       :init_project_for_new_user,
       System.get_env("INIT_PROJECT_FOR_NEW_USER", "false")
       |> String.to_atom()

# If you've booted up with a SENTRY_DSN environment variable, use Sentry!
config :sentry,
  filter: Lightning.SentryEventFilter,
  environment_name: config_env(),
  included_environments:
    if(System.get_env("SENTRY_DSN"), do: [config_env()], else: [])

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

# The webserver port will always prefer and environment variable _when_
# given, otherwise it uses the existing config and lastly defaults to 4000.
port =
  (System.get_env("PORT") ||
     Application.get_env(:lightning, LightningWeb.Endpoint)
     |> Keyword.get(:http, port: nil)
     |> Keyword.get(:port) ||
     4000)
  |> case do
    p when is_binary(p) -> String.to_integer(p)
    p when is_integer(p) -> p
  end

# Use the `PRIMARY_ENCRYPTION_KEY` env variable if available, else fall back
# to defaults.
# Defaults are set for `dev` and `test` modes.
config :lightning, Lightning.Vault,
  primary_encryption_key:
    System.get_env("PRIMARY_ENCRYPTION_KEY") ||
      Application.get_env(:lightning, Lightning.Vault, [])
      |> Keyword.get(:primary_encryption_key, nil)

# Binding to loopback ipv4 address prevents access from other machines.
# http: [ip: {0, 0, 0, 0}, port: 4000],
# Set `http.ip` to {127, 0, 0, 1} to block access from other machines.
# Note that this may interfere with Docker networking.
# Enable IPv6 and bind on all interfaces.
# Set it to {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
# See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
# for details about using IPv6 vs IPv4 and loopback vs public addresses.
listen_address =
  (System.get_env("LISTEN_ADDRESS") ||
     Application.get_env(:lightning, LightningWeb.Endpoint)
     |> Keyword.get(:http, ip: nil)
     |> Keyword.get(:ip) ||
     {127, 0, 0, 1})
  |> case do
    p when is_binary(p) ->
      p
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)
      |> List.to_tuple()

    p when is_tuple(p) ->
      p
  end

config :lightning, LightningWeb.Endpoint,
  http: [
    ip: listen_address,
    port: port,
    compress: true
  ]

if log_level = System.get_env("LOG_LEVEL") do
  config :logger, level: log_level |> String.to_atom()
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

  origins =
    case System.get_env("ORIGINS") do
      nil -> true
      str -> String.split(str, ",")
    end

  config :lightning, LightningWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    secret_key_base: secret_key_base,
    check_origin: origins,
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
  config :lightning, Lightning.Repo,
    pool_size: :erlang.system_info(:logical_processors_available) + 2
end
