defmodule LightningWeb.ChannelProxyPlug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Lightning.Channels

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["channels", channel_id | rest]} = conn, _opts) do
    case fetch_channel(channel_id) do
      {:ok, channel} ->
        forward_path = build_forward_path(rest)

        conn
        |> put_proxy_headers()
        |> Weir.proxy(
          upstream: channel.sink_url,
          path: forward_path,
          request_id: get_request_id(conn)
        )
        |> halt()

      :not_found ->
        conn |> send_resp(404, "Not Found") |> halt()
    end
  end

  def call(conn, _opts), do: conn

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

  defp put_proxy_headers(conn) do
    request_id = get_request_id(conn)
    original_host = get_req_header(conn, "host") |> List.first("")
    remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    existing_xff = get_req_header(conn, "x-forwarded-for") |> List.first()

    xff_value =
      if existing_xff, do: "#{existing_xff}, #{remote_ip}", else: remote_ip

    conn
    |> put_req_header("x-request-id", request_id)
    |> put_req_header("x-forwarded-for", xff_value)
    |> put_req_header("x-forwarded-host", original_host)
    |> put_req_header("x-forwarded-proto", to_string(conn.scheme))
  end

  defp get_request_id(conn) do
    case get_resp_header(conn, "x-request-id") do
      [id | _] -> id
      [] -> Ecto.UUID.generate()
    end
  end
end
