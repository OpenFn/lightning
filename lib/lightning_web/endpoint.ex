defmodule LightningWeb.Endpoint do
  use Sentry.PlugCapture

  use Phoenix.Endpoint, otp_app: :lightning

  @doc """
  For dynamically configuring the endpoint, such as loading data from
  environment variables or configuration files, Phoenix invokes the init/2
  callback on the endpoint, passing the atom :supervisor as the first argument
  and the endpoint configuration as second.
  """
  def init(_supervisor, config) do
    config =
      config
      |> Kernel.put_in([:url, :host], System.get_env("URL_HOST"))
      |> Kernel.put_in([:url, :scheme], System.get_env("URL_SCHEME"))
      |> Kernel.put_in([:url, :port], System.get_env("URL_PORT"))
      |> Kernel.put_in([:http, :port], System.get_env("PORT"))

    {:ok, config}
  end

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

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :lightning,
    gzip: true,
    only: ~w(assets fonts images favicon.ico robots.txt)

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
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug LightningWeb.Router
end
