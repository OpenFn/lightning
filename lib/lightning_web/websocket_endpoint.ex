defmodule LightningWeb.WebsocketEndpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :lightning

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_lightning_key",
    signing_salt: "XWf+17Ne"
  ]

  socket "/worker", LightningWeb.WorkerSocket,
    websocket: [error_handler: {LightningWeb.WorkerSocket, :handle_error, []}],
    longpoll: false

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Sentry.PlugContext

  plug Plug.Session, @session_options
end
