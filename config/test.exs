import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# mock adapter for tesla
config :tesla, Lightning.VersionControl.GithubClient, adapter: Tesla.Mock

config :tesla, Mix.Tasks.Lightning.InstallAdaptorIcons, adapter: Tesla.Mock

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# On certain machines we get db queue timeouts, so we raise `queue_target`
# from 50 to 100 to give the DBConnection some room to respond.
config :lightning, Lightning.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "lightning_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 15,
  queue_target: 100

config :lightning, Lightning.Vault,
  primary_encryption_key: "M1zzWU6Ego6jV/FUS7e/sj7yF9kRIutgR8uLQ9czrVc="

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :lightning, LightningWeb.Endpoint,
  url: [host: "localhost", port: 4002],
  http: [port: 4002],
  secret_key_base:
    "/8zedVJLxvmGGFoRExE3e870g7CGZZQ1Vq11A5MbQGPKOpK57MahVsPW6Wkkv61n",
  server: true

config :lightning, Lightning.Runtime.RuntimeManager,
  start: false,
  ws_url: "ws://localhost:4002/worker",
  env: [{"NODE_OPTIONS", "--dns-result-order=ipv4first"}]

# In test we don't send emails.
config :lightning, Lightning.Mailer, adapter: Swoosh.Adapters.Test

config :lightning, Lightning.AdaptorRegistry,
  use_cache: "test/fixtures/adaptor_registry_cache.json"

config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :lightning, Lightning.FailureAlerter,
  time_scale: 60_000,
  rate_limit: 3

config :lightning,
  schemas_path: "test/fixtures/schemas",
  adaptor_icons_path: "test/fixtures/adaptors/icons"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :junit_formatter,
  report_file: "elixir_test_report.xml",
  report_dir: "./test/reports",
  print_report_file: true,
  prepend_project_name?: true

config :lightning, Oban, testing: :inline

config :lightning, LightningWeb, allow_credential_transfer: true

# Enables / Displays the credential features for LightningWeb.CredentialLiveTest
config :lightning, LightningWeb,
  allow_credential_transfer: true,
  enable_google_credential: true

config :lightning, CLI, child_process_mod: FakeRambo

# https://opentelemetry.io/docs/instrumentation/erlang/testing/
config :opentelemetry, traces_exporter: :none

config :opentelemetry, :processors, [
  {:otel_simple_processor, %{}}
]
