import Config

config :credentials_service, CredentialsService.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "credentials_service_dev",
  pool_size: 10

config :credentials_service, CredentialsServiceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: false,
  debug_errors: true

config :logger, level: :debug
