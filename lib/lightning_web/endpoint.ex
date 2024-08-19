defmodule LightningWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :lightning
  alias LightningWeb.Plugs

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_lightning_key",
    signing_salt: "XWf+17Ne"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  socket "/worker", LightningWeb.WorkerSocket,
    websocket: [
      error_handler: {LightningWeb.WorkerSocket, :handle_error, []},
      compress: true,
      max_frame_size: 11_000_000
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
    only: LightningWeb.static_paths()

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

  plug Unplug,
    if: {LightningWeb.PromExPlugAuthorization, nil},
    do: {PromEx.Plug, prom_ex_module: Lightning.PromEx}

  @plug_extensions Application.compile_env(
                     :lightning,
                     Lightning.Extensions.Plugs,
                     []
                   )
  for {plug, mfa_opts} <- @plug_extensions do
    plug Replug, plug: plug, opts: mfa_opts
  end

  plug Replug,
    plug: Plug.Parsers,
    opts: {LightningWeb.PlugConfigs, :plug_parsers}

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug CORSPlug, origin: &Lightning.Config.cors_origin/0

  plug Plugs.WebhookAuth

  plug Sentry.PlugContext

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug LightningWeb.Router
end
