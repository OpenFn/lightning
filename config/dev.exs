import Config

# Configure your database
config :lightning, Lightning.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "lightning_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with esbuild to bundle .js and .css sources.
config :lightning, LightningWeb.Endpoint,
  url: [host: "localhost", port: 4000, scheme: "http"],
  http: [
    ip: {0, 0, 0, 0},
    port: 4000,
    compress: true
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "52IzqaXS4XPqCTDUSKzP4VDRpYmumPWMzWLvCG+RNLYZ8MogoRkfUr9ULKBVBLKy",
  watchers: [
    # Start the esbuild watcher by calling Esbuild.install_and_run(:default, args)
    esbuild:
      {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]},
    storybook_tailwind: {Tailwind, :install_and_run, [:storybook, ~w(--watch)]}
  ]

config :lightning,
  schemas_path: "priv/schemas",
  adaptor_icons_path: "priv/static/images/adaptors"

config :lightning, Lightning.Vault,
  primary_encryption_key: "M1zzWU6Ego6jV/FUS7e/sj7yF9kRIutgR8uLQ9czrVc="

config :lightning, Lightning.Runtime.RuntimeManager,
  start: true,
  env: [{"NODE_OPTIONS", "--dns-result-order=ipv4first"}]

config :lightning, is_resettable_demo: true

# Watch static and templates for browser reloading.
config :lightning, LightningWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/lightning_web/(live|components|views)/.*(ex|heex)$",
      ~r"lib/lightning_web/templates/.*(eex)$",
      ~r"storybook/.*(exs)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# https://davelucia.com/blog/observing-elixir-with-lightstep
if System.get_env("EXPORT_OTEL") == "true" do
  config :opentelemetry, :processors,
    otel_batch_processor: %{
      exporter: {:otel_exporter_stdout, []}
    }
else
  config :opentelemetry, traces_exporter: :none
end
