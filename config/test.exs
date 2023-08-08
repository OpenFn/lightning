import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# mock adapter for tesla 
config :tesla, Lightning.VersionControl.GithubClient, adapter: Tesla.Mock

cert = """
-----BEGIN RSA PRIVATE KEY-----
MIICWwIBAAKBgQDdlatRjRjogo3WojgGHFHYLugdUWAY9iR3fy4arWNA1KoS8kVw33cJibXr8bvwUAUparCwlvdbH6dvEOfou0/gCFQsHUfQrSDv+MuSUMAe8jzKE4qW+jK+xQU9a03GUnKHkkle+Q0pX/g6jXZ7r1/xAK5Do2kQ+X5xK9cipRgEKwIDAQABAoGAD+onAtVye4ic7VR7V50DF9bOnwRwNXrARcDhq9LWNRrRGElESYYTQ6EbatXS3MCyjjX2eMhu/aF5YhXBwkppwxg+EOmXeh+MzL7Zh284OuPbkglAaGhV9bb6/5CpuGb1esyPbYW+Ty2PC0GSZfIXkXs76jXAu9TOBvD0ybc2YlkCQQDywg2R/7t3Q2OE2+yo382CLJdrlSLVROWKwb4tb2PjhY4XAwV8d1vy0RenxTB+K5Mu57uVSTHtrMK0GAtFr833AkEA6avx20OHo61Yela/4k5kQDtjEf1N0LfI+BcWZtxsS3jDM3i1Hp0KSu5rsCPb8acJo5RO26gGVrfAsDcIXKC+bQJAZZ2XIpsitLyPpuiMOvBbzPavd4gY6Z8KWrfYzJoI/Q9FuBo6rKwl4BFoToD7WIUS+hpkagwWiz+6zLoX1dbOZwJACmH5fSSjAkLRi54PKJ8TFUeOP15h9sQzydI8zJU+upvDEKZsZc/UhT/SySDOxQ4G/523Y0sz/OZtSWcol/UMgQJALesy++GdvoIDLfJX5GBQpuFgFenRiRDabxrE9MNUZ2aPFaFp+DyAe+b4nDwuJaW2LURbr8AEZga7oQj0uYxcYw==
-----END RSA PRIVATE KEY----- 
"""

System.put_env("GITHUB_CERT", Base.encode64(cert))

config :lightning, :github_app,
  cert: cert,
  app_id: "111111"

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
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "/8zedVJLxvmGGFoRExE3e870g7CGZZQ1Vq11A5MbQGPKOpK57MahVsPW6Wkkv61n",
  server: false

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
  schemas_path: "test/fixtures/schemas"

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
