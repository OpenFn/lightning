defmodule LightningWeb.ChannelProxyPlug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Lightning.Channels

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["channels", channel_id | rest]} = conn, _opts) do
    metadata = %{channel_id: channel_id}

    :telemetry.span(
      [:lightning, :channel_proxy, :request],
      metadata,
      fn ->
        result = do_proxy(conn, channel_id, rest)
        {result, metadata}
      end
    )
  end

  def call(conn, _opts), do: conn

  defp do_proxy(conn, channel_id, rest) do
    case fetch_channel_with_telemetry(channel_id) do
      {:ok, channel} ->
        case Channels.get_or_create_current_snapshot(channel) do
          {:ok, snapshot} ->
            forward_path = build_forward_path(rest)

            conn
            |> put_proxy_headers()
            |> proxy_upstream(channel, snapshot, forward_path)
            |> halt()

          {:error, _} ->
            conn |> send_resp(500, "Internal Server Error") |> halt()
        end

      :not_found ->
        conn |> send_resp(404, "Not Found") |> halt()
    end
  end

  defp fetch_channel_with_telemetry(channel_id) do
    metadata = %{channel_id: channel_id}

    :telemetry.span(
      [:lightning, :channel_proxy, :fetch_channel],
      metadata,
      fn ->
        result = fetch_channel(channel_id)
        {result, metadata}
      end
    )
  end

  defp proxy_upstream(conn, channel, snapshot, forward_path) do
    handler_state = %{
      channel: channel,
      snapshot: snapshot,
      started_at: DateTime.utc_now(),
      request_path: "/" <> Enum.join(conn.path_info, "/"),
      client_identity: get_client_identity(conn)
    }

    metadata = %{
      channel_id: channel.id,
      sink_url: channel.sink_url,
      path: forward_path
    }

    :telemetry.span(
      [:lightning, :channel_proxy, :upstream],
      metadata,
      fn ->
        result =
          Weir.proxy(conn,
            upstream: channel.sink_url,
            path: forward_path,
            handler: {Lightning.Channels.Handler, handler_state}
          )

        {result, metadata}
      end
    )
  end

  defp fetch_channel(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Channels.Channel{enabled: true} = channel <-
           Channels.get_channel(uuid) do
      {:ok, channel}
    else
      _ -> :not_found
    end
  end

  defp build_forward_path([]), do: "/"
  defp build_forward_path(segments), do: "/" <> Enum.join(segments, "/")

  defp get_client_identity(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [xff | _] -> xff |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp put_proxy_headers(conn) do
    original_host = get_req_header(conn, "host") |> List.first("")
    remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    existing_xff = get_req_header(conn, "x-forwarded-for") |> List.first()

    xff_value =
      if existing_xff, do: "#{existing_xff}, #{remote_ip}", else: remote_ip

    conn
    |> put_req_header("x-forwarded-for", xff_value)
    |> put_req_header("x-forwarded-host", original_host)
    |> put_req_header("x-forwarded-proto", to_string(conn.scheme))
  end
end
