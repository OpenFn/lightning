# benchmarking/channels/mock_sink.exs
#
# A standalone HTTP sink server for testing the channel proxy.
# Accepts all requests on any path and responds according to the
# configured mode. Useful for integration tests, load tests, and
# manual exploration of the proxy pipeline.
#
# Usage:
#   elixir benchmarking/channels/mock_sink.exs [options]
#
# Examples:
#   elixir benchmarking/channels/mock_sink.exs
#   elixir benchmarking/channels/mock_sink.exs --port 9000 --status 201
#   elixir benchmarking/channels/mock_sink.exs --mode auth
#   elixir benchmarking/channels/mock_sink.exs --mode mixed

Mix.install([:bandit, :plug, :jason])

defmodule MockSink.Config do
  @moduledoc """
  Parses CLI arguments into a configuration map and prints help text.
  """

  @defaults %{
    port: 4001,
    mode: "fixed",
    status: 200,
    body_size: 256
  }

  @help """
  Usage: elixir benchmarking/channels/mock_sink.exs [options]

  A configurable HTTP sink server for testing the channel proxy.

  Options:
    --port PORT          Listen port (default: 4001)
    --mode MODE          Response mode (default: fixed)
                         Modes: fixed, timeout, auth, mixed
    --status CODE        Response status code for fixed mode (default: 200)
    --body-size BYTES    Response body size in bytes (default: 256)
    --help               Show this help

  Query parameters (per-request overrides):
    ?response_size=N   Override --body-size for this request (bytes)
    ?delay=N           Add a response delay for this request (ms)
    ?status=N          Override --status for this request (100-599)

  Modes:
    fixed      Returns --status with --body-size body.
    timeout    Accepts the connection but never responds.
    auth       Checks Authorization header. 401 if missing, 403 if invalid,
               200 if valid. Expected: "Bearer test-api-key".
    mixed      80% fast 200, 10% slow 200 (2s delay), 10% 503.
  """

  def parse(args) do
    case parse_args(args, @defaults) do
      :help ->
        IO.puts(@help)
        System.halt(0)

      {:error, message} ->
        IO.puts(:stderr, "error: #{message}\n")
        IO.puts(:stderr, @help)
        System.halt(1)

      config ->
        validate!(config)
    end
  end

  defp parse_args([], acc), do: acc

  defp parse_args(["--help" | _rest], _acc), do: :help

  defp parse_args(["--port", value | rest], acc) do
    case Integer.parse(value) do
      {port, ""} when port > 0 -> parse_args(rest, %{acc | port: port})
      _ -> {:error, "invalid port: #{value}"}
    end
  end

  defp parse_args(["--mode", value | rest], acc) do
    if value in ~w(fixed timeout auth mixed) do
      parse_args(rest, %{acc | mode: value})
    else
      {:error, "unknown mode: #{value}. Expected: fixed, timeout, auth, mixed"}
    end
  end

  defp parse_args(["--status", value | rest], acc) do
    case Integer.parse(value) do
      {code, ""} when code >= 100 and code < 600 ->
        parse_args(rest, %{acc | status: code})

      _ ->
        {:error, "invalid status code: #{value}"}
    end
  end

  defp parse_args(["--body-size", value | rest], acc) do
    case Integer.parse(value) do
      {bytes, ""} when bytes >= 0 -> parse_args(rest, %{acc | body_size: bytes})
      _ -> {:error, "invalid body-size: #{value}"}
    end
  end

  defp parse_args([unknown | _rest], _acc) do
    {:error, "unknown option: #{unknown}"}
  end

  defp validate!(config) when is_map(config), do: config
end

defmodule MockSink.Logger do
  @moduledoc """
  Simple request logging to stdout.
  """

  def log_request(method, path, status, elapsed_ms) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S.%f")

    IO.puts(
      "[#{timestamp}] #{String.upcase(method)} #{path} -> #{status} (#{elapsed_ms}ms)"
    )
  end
end

defmodule MockSink.Body do
  @moduledoc """
  Generates response bodies of the configured size.
  Small payloads (<= 1024 bytes) get a JSON envelope; larger ones are
  padded with a repeated character to hit the exact byte count.
  """

  def generate(body_size) when body_size <= 1024 do
    json =
      Jason.encode!(%{
        ok: true,
        server: "mock_sink",
        timestamp: DateTime.to_iso8601(DateTime.utc_now()),
        padding: String.duplicate("x", max(body_size - 80, 0))
      })

    # Trim or pad to reach the target size exactly.
    byte_size = byte_size(json)

    cond do
      byte_size == body_size -> json
      byte_size > body_size -> binary_part(json, 0, body_size)
      true -> json <> String.duplicate(" ", body_size - byte_size)
    end
  end

  def generate(body_size) do
    String.duplicate("x", body_size)
  end
end

defmodule MockSink.Router do
  @moduledoc """
  Plug router that handles all incoming requests according to the
  configured mode. Config is injected via `conn.private[:mock_config]`.
  """

  use Plug.Router

  plug :put_config
  plug :match

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    json_decoder: Jason,
    pass: ["*/*"]

  plug :dispatch

  # ------------------------------------------------------------------
  # Plug: inject config into conn.private so downstream handlers can
  # read it without global state.
  # ------------------------------------------------------------------
  def put_config(conn, _opts) do
    Plug.Conn.put_private(conn, :mock_config, conn.assigns[:mock_config])
  end

  @impl Plug.Router
  def init(config) do
    config
  end

  @impl Plug.Router
  def call(conn, config) do
    conn
    |> Plug.Conn.assign(:mock_config, config)
    |> super(config)
  end

  # ------------------------------------------------------------------
  # Catch-all route
  # ------------------------------------------------------------------
  match _ do
    config = conn.private[:mock_config]
    config = apply_query_overrides(conn, config)
    start = System.monotonic_time(:millisecond)

    {status, body, content_type} = handle_mode(conn, config)

    elapsed = System.monotonic_time(:millisecond) - start

    MockSink.Logger.log_request(
      conn.method,
      conn.request_path,
      status,
      elapsed
    )

    conn
    |> Plug.Conn.put_resp_content_type(content_type)
    |> Plug.Conn.send_resp(status, body)
  end

  # ------------------------------------------------------------------
  # Query param overrides
  # ------------------------------------------------------------------
  defp apply_query_overrides(conn, config) do
    conn = Plug.Conn.fetch_query_params(conn)

    config
    |> override_param(conn, "response_size", :body_size)
    |> override_param(conn, "delay", :delay)
    |> override_param(conn, "status", :status)
  end

  defp override_param(config, conn, param, key) do
    case conn.query_params[param] do
      nil ->
        config

      value ->
        case Integer.parse(value) do
          {n, ""} when n >= 0 -> Map.put(config, key, n)
          _ -> config
        end
    end
  end

  # ------------------------------------------------------------------
  # Mode handlers
  # ------------------------------------------------------------------
  defp handle_mode(_conn, %{mode: "fixed"} = config) do
    delay = Map.get(config, :delay, 0)
    if delay > 0, do: Process.sleep(delay)
    body = MockSink.Body.generate(config.body_size)
    {config.status, body, content_type(config.body_size)}
  end

  defp handle_mode(_conn, %{mode: "timeout"}) do
    # Accept the connection but never respond.
    # The client will eventually time out.
    Process.sleep(:infinity)
    # Unreachable, but keeps the typespec happy.
    {200, "", "text/plain"}
  end

  defp handle_mode(conn, %{mode: "auth"} = config) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      [] ->
        body = Jason.encode!(%{error: "missing authorization header"})
        {401, body, "application/json"}

      ["Bearer test-api-key"] ->
        body = MockSink.Body.generate(config.body_size)
        {200, body, content_type(config.body_size)}

      [_invalid] ->
        body = Jason.encode!(%{error: "invalid credentials"})
        {403, body, "application/json"}

      _ ->
        body = Jason.encode!(%{error: "invalid authorization header"})
        {400, body, "application/json"}
    end
  end

  defp handle_mode(_conn, %{mode: "mixed"} = config) do
    roll = :rand.uniform()

    cond do
      # 10% — 503 Service Unavailable
      roll > 0.9 ->
        body = Jason.encode!(%{error: "service unavailable"})
        {503, body, "application/json"}

      # 10% — slow 200 (2 second delay)
      roll > 0.8 ->
        Process.sleep(2000)
        body = MockSink.Body.generate(config.body_size)
        {200, body, content_type(config.body_size)}

      # 80% — fast 200
      true ->
        body = MockSink.Body.generate(config.body_size)
        {200, body, content_type(config.body_size)}
    end
  end

  defp content_type(body_size) when body_size <= 1024, do: "application/json"
  defp content_type(_body_size), do: "application/octet-stream"
end

defmodule MockSink do
  @moduledoc """
  Entry point. Parses CLI args, prints a banner, and starts Bandit.
  """

  def main(args) do
    config = MockSink.Config.parse(args)

    IO.puts("""

    ===================================================
      MockSink starting on port #{config.port}
      Mode:      #{config.mode}
      Status:    #{config.status}
      Body size: #{config.body_size} bytes
    ===================================================
    """)

    {:ok, _} =
      Bandit.start_link(
        plug: {MockSink.Router, config},
        port: config.port,
        thousand_island_options: [
          num_acceptors: 10
        ]
      )

    # Block the script forever so the server stays up.
    Process.sleep(:infinity)
  end
end

MockSink.main(System.argv())
