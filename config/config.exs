# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :lightning,
  ecto_repos: [Lightning.Repo]

config :lightning, Lightning.Repo,
  types: Lightning.PostgrexTypes,
  log: :debug

config :hammer,
  backend:
    {Hammer.Backend.Mnesia,
     [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Configures the endpoint
config :lightning, LightningWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    view: LightningWeb.ErrorView,
    accepts: ~w(html json),
    layout: false
  ],
  pubsub_server: Lightning.PubSub,
  live_view: [signing_salt: "EfrmuOUr"]

config :lightning, Lightning.Extensions,
  rate_limiter: Lightning.Extensions.RateLimiter,
  usage_limiter: Lightning.Extensions.UsageLimiter,
  run_queue: Lightning.Extensions.FifoRunQueue

config :joken, default_signer: "secret"

# Configures the mechanism for erlang node clustering
config :libcluster,
  topologies: [
    local: [strategy: Cluster.Strategy.Gossip]
  ]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :lightning, Lightning.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, Swoosh.ApiClient.Hackney

# Set OAuth2 to use Hackney for HTTP calls
config :oauth2, adapter: Tesla.Adapter.Hackney

config :lightning, :oauth_clients,
  google: [
    wellknown_url: "https://accounts.google.com/.well-known/openid-configuration"
  ],
  salesforce: [
    prod_wellknown_url:
      "https://login.salesforce.com/.well-known/openid-configuration",
    sandbox_wellknown_url:
      "https://test.salesforce.com/.well-known/openid-configuration"
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.18",
  default: [
    args:
      ~w(js/app.js
         js/storybook.js
         js/editor/Editor.tsx
         fonts/inter.css
         fonts/fira-code.css
         --loader:.woff2=file
         --format=esm --splitting --bundle
         --target=es2020
         --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# https://fly.io/phoenix-files/tailwind-standalone/
config :tailwind,
  version: "3.3.5",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ],
  storybook: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/storybook.css
      --output=../priv/static/assets/storybook.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :lightning, Lightning.Vault, json_library: Jason

config :lightning, Lightning.FailureAlerter,
  time_scale: 5 * 60_000,
  rate_limit: 3

# Disables / Hides the credential transfer feature for beta (in LightningWeb.CredentialLive.Edit)
config :lightning, LightningWeb, allow_credential_transfer: false

# Rather than default  since httpc doesnt have certificate checking
config :tesla, adapter: Tesla.Adapter.Hackney

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
