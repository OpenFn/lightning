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
    websocket: [error_handler: {LightningWeb.WorkerSocket, :handle_error, []}],
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

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plugs.WebhookAuth

  plug Plug.Parsers,
    parsers: [
      :urlencoded,
      :multipart,
      # Increase to 10MB max request size only for JSON parser
      {:json, length: 10_000_000}
    ],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug LightningWeb.Router
end
