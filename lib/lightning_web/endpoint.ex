defmodule LightningWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :lightning

  alias LightningWeb.Plugs

  require LightningWeb.Utils

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_lightning_key",
    signing_salt: "XWf+17Ne"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [:peer_data, :uri, :user_agent, session: @session_options]
    ]

  socket "/worker", LightningWeb.WorkerSocket,
    websocket: [
      error_handler: {LightningWeb.WorkerSocket, :handle_error, []},
      compress: true,
      max_frame_size: 11_000_000
    ],
    longpoll: false

  socket "/socket", LightningWeb.UserSocket,
    websocket: [
      error_handler: {LightningWeb.UserSocket, :handle_error, []},
      connect_info: [:peer_data, :uri, :user_agent],
      compress: true
    ],
    longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :lightning,
    gzip: true,
    only: LightningWeb.static_paths(),
    headers: [
      {"x-content-type-options", "nosniff"}
    ]

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :lightning
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId

  # Channel proxy — must be before Plug.Parsers to preserve raw body
  plug LightningWeb.ChannelProxyPlug

  plug Plugs.PromexWrapper

  @pre_parsers_plugs Application.compile_env(
                       :lightning,
                       Lightning.Extensions.PreParsersPlugs,
                       []
                     )

  LightningWeb.Utils.add_dynamic_plugs(@pre_parsers_plugs)

  plug CORSPlug, origin: &Lightning.Config.cors_origin/0

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Sentry.PlugContext

  plug Plugs.WebhookAuth

  plug Replug,
    plug: Plug.Parsers,
    opts: {LightningWeb.PlugConfigs, :plug_parsers}

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  @post_session_plugs Application.compile_env(
                        :lightning,
                        Lightning.Extensions.PostSessionPlugs,
                        []
                      )

  LightningWeb.Utils.add_dynamic_plugs(@post_session_plugs)

  plug LightningWeb.Router
end
