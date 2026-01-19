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
  run_queue: Lightning.Extensions.FifoRunQueue,
  account_hook: Lightning.Extensions.AccountHook,
  collection_hook: Lightning.Extensions.CollectionHook,
  project_hook: Lightning.Extensions.ProjectHook,
  external_metrics: Lightning.Extensions.ExternalMetrics

config :lightning, Lightning.Extensions.Routing,
  session_opts: [on_mount: LightningWeb.InitAssigns],
  routes: [
    {"/projects", LightningWeb.DashboardLive.Index, :index, []},
    {"/projects/:project_id/settings", LightningWeb.ProjectLive.Settings, :index,
     metadata: %{
       concurrency_input: LightningWeb.ProjectLive.ConcurrencyInputComponent
     }},
    {"/profile", LightningWeb.ProfileLive.Edit, :edit,
     metadata: %{delete_modal: LightningWeb.Components.UserDeletionModal}},
    {"/settings/users", LightningWeb.UserLive.Index, :index, []}
  ]

# TODO: don't use this value in production
config :joken, default_signer: "secret"

config :lightning, Lightning.Runtime.RuntimeManager,
  start: false,
  env: [{"NODE_OPTIONS", "--dns-result-order=ipv4first"}]

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

# Configure esbuild (the version is required)
# TODO: work out how to _NOT_ have this set of entry points try and build
# monaco-editor, since we already have a separate esbuild task for that.
# Note the `--external:path` flag, this is to work around a recent change
# in esbuild causing it to fail when trying to bundle up the @typescript/vfs module
# but only when minifying.
config :esbuild,
  version: "0.25.0",
  default: [
    args:
      ~w(--loader:.woff2=file
         --loader:.ttf=copy
         --format=esm --splitting --bundle
         --external:path
         --jsx=automatic
         --tsconfig=tsconfig.browser.json
         --target=es2020
         --outdir=../priv/static/assets
         --external:path
         --external:/fonts/*
         --external:/images/*
         js/app.js
         js/storybook.js
         js/editor/Editor.tsx
         js/react/components/DataclipViewer.tsx
         js/job-editor/JobEditor.tsx
         js/workflow-editor/WorkflowEditor.tsx
         js/workflow-store/WorkflowStore.tsx
         js/manual-run-panel/ManualRunPanel.tsx
         js/panel/panels/WorkflowRunPanel.tsx
         js/collaborative-editor/CollaborativeEditor.tsx
         editor.worker=monaco-editor/esm/vs/editor/editor.worker.js
         json.worker=monaco-editor/esm/vs/language/json/json.worker.js
         css.worker=monaco-editor/esm/vs/language/css/css.worker.js
         html.worker=monaco-editor/esm/vs/language/html/html.worker.js
         typescript.worker=monaco-editor/esm/vs/language/typescript/ts.worker.js
         codicon=monaco-editor/esm/vs/base/browser/ui/codicons/codicon/codicon.ttf
         fonts/inter.css
         fonts/fira-code.css
        )
      |> then(fn args ->
        case config_env() do
          :prod ->
            args ++ ["--define:ENABLE_DEVTOOLS=false"]

          _ ->
            args ++ ["--jsx-dev", "--define:ENABLE_DEVTOOLS=true"]
        end
      end),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# https://fly.io/phoenix-files/tailwind-standalone/
config :tailwind,
  version: "4.1.14",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ],
  storybook: [
    args: ~w(
      --input=assets/css/storybook.css
      --output=priv/static/assets/storybook.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :session_id,
    :prompt_size,
    :credential_id,
    :run_id,
    :project_id,
    :project_env
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :lightning, Lightning.Vault, json_library: Jason

config :lightning, Lightning.FailureAlerter,
  time_scale: 5 * 60_000,
  rate_limit: 3

# Disables / Hides the credential transfer feature for beta (in LightningWeb.CredentialLive.Edit)
config :lightning, LightningWeb, allow_credential_transfer: false

config :tesla, adapter: {Tesla.Adapter.Finch, name: Lightning.Finch}

config :lightning, :is_resettable_demo, false
config :lightning, :default_retention_period, nil
config :lightning, :claim_work_mem, nil

config :lightning, Lightning.Runtime.RuntimeManager, start: false

config :lightning, LightningWeb.CollectionsController,
  default_stream_limit: 1_000,
  max_database_limit: 500

# Configuration for injecting a custom feedback mechanism or component collection
# for the AI Assistant. This can include interactive elements such as a button
# that triggers a modal with a survey form, or a PostHog component to capture
# user feedback on AI Assistant messages.

# Example:
# To enable feedback using a custom component, you can configure it as follows:
#
# config :lightning, :ai_feedback, %{
#   component: &LightningWeb.Components.open_feedback_modal/1
# }
#
# To disable the feedback mechanism, set the value to `false` as shown below:
config :lightning, :ai_feedback, false

# Configuration for GDPR Compliance Components
#
# The GDPR configuration allows you to enable or disable user consent management
# features across your application. This includes both a notification banner and
# preference management components that handle user consent for data processing
# activities in compliance with GDPR regulations.
#
# -------------------------
# GDPR Banner Configuration
# -------------------------
#
# The banner appears to users who have not yet specified their privacy preferences.
# It provides information about data processing activities and prompts the user
# to make choices about cookie and data usage.
#
# Example:
# To enable the GDPR banner with a custom component:
#
# config :lightning, :gdpr_banner, %{
#   component: MyAppWeb.Components.CookieConsentBanner,
#   id: "cookie-consent-banner"
# }
#
# ------------------------------
# GDPR Preferences Configuration
# ------------------------------
#
# The preferences component provides an interface for users to view and modify
# their consent settings for various data processing activities.
#
# Example:
# To enable GDPR preferences management with a custom component:
#
# config :lightning, :gdpr_preferences, %{
#   component: MyAppWeb.Components.CookiePreferencesComponent,
#   id: "cookie-consent-preferences"
# }
#
# -----------------------
# Disabling GDPR Components
# -----------------------
#
# To disable either or both GDPR components, set their values to `false`:
config :lightning, :gdpr_preferences, false
config :lightning, :gdpr_banner, false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
