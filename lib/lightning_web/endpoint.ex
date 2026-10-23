defmodule LightningWeb.Endpoint do
  @moduledoc """
  The HTTP entry point. It declares the sockets and the plugs every request
  passes through before `LightningWeb.Router`.

  A raise on a problem path is answered in `LightningWeb.Endpoint.call/2` and
  nowhere else. `ProblemPaths.answers?/2` is the only place that says which
  raises qualify (error-format spec §5), and `Codes.for_exception/2` the only
  place that says which code a raise gets: its own status if a client caused
  it, and a 500 for anything a client did not cause.
  """

  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :lightning

  alias LightningWeb.API.Codes
  alias LightningWeb.API.Problem
  alias LightningWeb.API.ProblemPaths
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

  @cors_options [origin: &Lightning.Config.cors_origin/0]

  plug Plug.RequestId

  plug CORSPlug, @cors_options

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Channel proxy — must be before Plug.Parsers to preserve raw body
  plug LightningWeb.ChannelProxyPlug

  plug Plugs.PromexWrapper

  @pre_parsers_plugs Application.compile_env(
                       :lightning,
                       Lightning.Extensions.PreParsersPlugs,
                       []
                     )

  LightningWeb.Utils.add_dynamic_plugs(@pre_parsers_plugs)

  plug Sentry.PlugContext,
    header_scrubber: {LightningWeb.SentryScrubber, :scrub_headers}

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

  # Wraps the plug pipeline from inside Sentry's and Phoenix's own call/2
  # wrappers, so it sees the request's path and Accept whether the raise came
  # before the router or inside it.
  def call(conn, opts) do
    super(conn, opts)
  rescue
    e in Plug.Conn.WrapperError ->
      %{conn: conn, kind: kind, reason: reason, stack: stack} = e

      case answer_raise(conn, kind, reason, stack, & &1) do
        # Keep the wrapper so Phoenix renders with the router's conn and format.
        :raise -> reraise e, __STACKTRACE__
        conn -> conn
      end
  catch
    kind, reason ->
      case answer_raise(conn, kind, reason, __STACKTRACE__, &put_entry_headers/1) do
        :raise -> :erlang.raise(kind, reason, __STACKTRACE__)
        conn -> conn
      end
  end

  # A raise, exit or throw that Plug did not wrap leaves only the conn that
  # entered call/2, so an answer to it lacks the headers the endpoint's plugs
  # set. The preflight response is off so that an OPTIONS request still gets
  # the error, not a 204.
  defp put_entry_headers(conn) do
    conn
    |> put_request_id()
    |> CORSPlug.call(
      CORSPlug.init([send_preflight_response?: false] ++ @cors_options)
    )
  end

  # Plug.RequestId would mint a fresh id when the request sent none, and the
  # answer would not match the id the request's log lines already carry.
  defp put_request_id(conn) do
    case Logger.metadata()[:request_id] do
      nil -> Plug.RequestId.call(conn, Plug.RequestId.init([]))
      request_id -> Plug.Conn.put_resp_header(conn, "x-request-id", request_id)
    end
  end

  defp answer_raise(conn, kind, reason, stack, prepare) do
    exception = Exception.normalize(kind, reason, stack)

    if ProblemPaths.answers?(conn, exception) do
      code = Codes.for_exception(kind, exception)
      conn = respond_unless_sent(prepare.(conn), Problem.new(code))

      # Raise the 500 after answering it, so Sentry and Phoenix still log the
      # crash.
      if code == :internal, do: :raise, else: Plug.Conn.halt(conn)
    else
      :raise
    end
  end

  # The same check Phoenix.Endpoint.RenderErrors makes: send_resp/3 tells the
  # owner process, so a response a plug sent before raising is left alone.
  defp respond_unless_sent(conn, problem) do
    receive do
      {:plug_conn, :sent} ->
        send(self(), {:plug_conn, :sent})
        %Plug.Conn{conn | state: :sent}
    after
      0 -> Problem.respond(conn, problem)
    end
  end
end
