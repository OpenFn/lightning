import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# mock adapter for tesla
config :tesla, adapter: Lightning.Tesla.Mock

config :tesla, Lightning.AuthProviders.OauthHTTPClient,
  adapter: Lightning.AuthProviders.OauthHTTPClient.Mock

config :tesla, Mix.Tasks.Lightning.InstallAdaptorIcons, adapter: Tesla.Mock

config :tesla, Lightning.UsageTracking.Client, adapter: Tesla.Mock
config :tesla, Lightning.UsageTracking.GithubClient, adapter: Tesla.Mock

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#

# If we are running a performance test, set the ownership timeout to infinity.
ownership_timeout =
  if System.get_env("PERFORMANCE_TEST") do
    :infinity
  else
    120_000
  end

# On certain machines we get db queue timeouts, so we raise `queue_target`
# from 50 to 100 to give the DBConnection some room to respond.
config :lightning, Lightning.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "lightning_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 15,
  queue_target: 100,
  ownership_timeout: ownership_timeout

config :lightning, Lightning.Vault,
  primary_encryption_key: "M1zzWU6Ego6jV/FUS7e/sj7yF9kRIutgR8uLQ9czrVc="

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :lightning, LightningWeb.Endpoint,
  http: [port: 4002],
  secret_key_base:
    "/8zedVJLxvmGGFoRExE3e870g7CGZZQ1Vq11A5MbQGPKOpK57MahVsPW6Wkkv61n",
  server: true

config :lightning, Lightning.Runtime.RuntimeManager,
  ws_url: "ws://localhost:4002/worker"

config :lightning, :workers,
  private_key: """
  -----BEGIN PRIVATE KEY-----
  MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCpnpkjo7vhBrXa
  cQk4xufVKZgWnb0b1UFHd52b2Zi3Qo4R+5+QNRc7hzxvDjJQ2tJ2l4cxjfuoad3h
  FyiHRRMdVTsSqa/1S0dk9ws9aN/gGEow+EIN2/RY4JW5f0xYDRx84lT7n7gxesbp
  82KNL/LO8ZnKzIEEnKy0zbMA3vLGW8sVhpS9QRRql4VukkNo4eZvavCL6DCCn9Rj
  Z7ykKHNlOxMDdmHbxD1c7mPspumRodS0+w/p9kr70XnWx2Itsnzs8DUz1GE70yc7
  jfR/od7VTv5k3vYMDwOqolSH8LZrIpaopB7AberqCuvgGsuOO3vM+6biddfFQPL0
  hsohrq/FAgMBAAECggEABHV4DrXJKvswLW13RP5r+oojYCs5XQS+hV07NjoCh7ha
  LIk+z12pHkl9AmmPIEAzjcAh/HpNBhPyXzs3arobUu2tcqolrZism2NBimKG/OJM
  +pVfUMBaRgcK9VthUf2jC0b8qoV78OEKkmMLHi1ts2Vds5t4o/rL/dzCbeChsfeN
  mRWaAAAADdaPAU9rX0G72V0GzjpSn8tbymMghwdKTSjt5Xr8s7zGmD5MoIwL47d3
  O/z9FwdfjYkdXbn30+BOcdpGWU9TfY7EpcTETCwkYXREcdqgKSGSg+M55C9Moc+E
  2OuSsKtht/A6OXuqCORymRScACc5OLAWvMkX0xncgQKBgQDdLAgASDmM8giPfUdz
  GyQ+IUXYtx91xqOW0uuqQ7V/PcUmXqdKs8vaRxlQ0j9hqsvMuu4iUa6j/qBrCai9
  mZh2IczrrIub7LB0p3ZzTLmqLSxAWKYML6/MOV7AyuY7Xt8wiNYaikELf/wu7DUD
  G+hwVe0TZMBnerRHrxwXeyyHMQKBgQDEVF1Alvfyx+Bxpxwc4N07quqj6zPytScJ
  xaoPUoIXVYVH4T6/YJLRQEHV/m2HV6+cmAD/x8L1nAesfAayNoaw8PPTXiRVym5k
  KMYu+amJAAIBygcK8c8w7NCY4NL2g6brYPInPnxnF/tHEgybudDzdnYikG2chr5x
  18dUpmB01QKBgQCHs+N44NfG3h5YhCKZwpZ7NIkZjkpURjvLZ8DHKGItHyZfA4ab
  tDOoyyUCTO4sq9H93NgN4JZJ8wpUgomxQ5OjL9v+4lCKrDAccz+fQP1OKAdVt86x
  /XRc1vqHSjb3SJ+itOLBSADe4HlIBRAFx1LX0jDzTEctdsE0loGi+qV4kQKBgGtZ
  HawFYAmVlHlQQCTiJtVLPQTnw/2/Y1sKg1Phb1RG5JtK475Mlbpoghb6CPVp0pGy
  40j39vfImsGLBzZGbhsthIRcA04NY5LMYKCqzjIkmPRVfMhVM06zDdOpinBTx98H
  oSAoIGlWSYSwr8guL7wPV8TKZ8SgQF2K+GimmDMJAoGANA0h5UNuHFZI8cg7SwR3
  UHrjyn9sMGQcn6CUnpgHEtZa9i0Dw4Wcx0j7KcKV68XIIisIqRweFDvgrUC/XJiD
  8awEXEW3Y84FisbI3snDpqTHIPnsh4zaJfbHzr4HEeW9qeCKbmYrvC+nQJD+vu3J
  3wneQ/c7fH6DI81VAtBtMWA=
  -----END PRIVATE KEY-----
  """,
  worker_secret: "ZOr2sjacHZnql7WYETL2x61d6RDdecnyLWieoG+bX6Q="

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
  adaptor_icons_path: "test/fixtures/adaptors/icons",
  repo_connection_signing_secret:
    "39h9Qr6+v2wgzjlh4xQoJ90aDe+LY7qIvA5v7QLsTwIwGDfs8el9Z0oFk2Ege33E"

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
config :lightning, LightningWeb, allow_credential_transfer: true

config :lightning, CLI, child_process_mod: FakeRambo

# https://opentelemetry.io/docs/instrumentation/erlang/testing/
config :opentelemetry, traces_exporter: :none

config :opentelemetry, :processors, [
  {:otel_simple_processor, %{}}
]

config :lightning, :is_resettable_demo, true

config :lightning, :github_app,
  app_id: "111111",
  app_name: "test-github",
  client_id: "abcd1234",
  client_secret: "client1234",
  cert: """
  -----BEGIN RSA PRIVATE KEY-----
  MIICWwIBAAKBgQDdlatRjRjogo3WojgGHFHYLugdUWAY9iR3fy4arWNA1KoS8kVw
  33cJibXr8bvwUAUparCwlvdbH6dvEOfou0/gCFQsHUfQrSDv+MuSUMAe8jzKE4qW
  +jK+xQU9a03GUnKHkkle+Q0pX/g6jXZ7r1/xAK5Do2kQ+X5xK9cipRgEKwIDAQAB
  AoGAD+onAtVye4ic7VR7V50DF9bOnwRwNXrARcDhq9LWNRrRGElESYYTQ6EbatXS
  3MCyjjX2eMhu/aF5YhXBwkppwxg+EOmXeh+MzL7Zh284OuPbkglAaGhV9bb6/5Cp
  uGb1esyPbYW+Ty2PC0GSZfIXkXs76jXAu9TOBvD0ybc2YlkCQQDywg2R/7t3Q2OE
  2+yo382CLJdrlSLVROWKwb4tb2PjhY4XAwV8d1vy0RenxTB+K5Mu57uVSTHtrMK0
  GAtFr833AkEA6avx20OHo61Yela/4k5kQDtjEf1N0LfI+BcWZtxsS3jDM3i1Hp0K
  Su5rsCPb8acJo5RO26gGVrfAsDcIXKC+bQJAZZ2XIpsitLyPpuiMOvBbzPavd4gY
  6Z8KWrfYzJoI/Q9FuBo6rKwl4BFoToD7WIUS+hpkagwWiz+6zLoX1dbOZwJACmH5
  fSSjAkLRi54PKJ8TFUeOP15h9sQzydI8zJU+upvDEKZsZc/UhT/SySDOxQ4G/523
  Y0sz/OZtSWcol/UMgQJALesy++GdvoIDLfJX5GBQpuFgFenRiRDabxrE9MNUZ2aP
  FaFp+DyAe+b4nDwuJaW2LURbr8AEZga7oQj0uYxcYw==
  -----END RSA PRIVATE KEY-----
  """

config :lightning, Lightning.Collections, query_all_limit: 50
