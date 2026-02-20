defmodule LightningWeb.ChannelProxyPlug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Lightning.Channels
  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Repo
  alias LightningWeb.Auth

  require Logger

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
    with {:ok, channel} <- fetch_channel_with_telemetry(channel_id),
         :ok <- authenticate_source(conn, channel) do
      proxy_with_auth(conn, channel, rest)
    else
      :not_found -> error_response(conn, :not_found, "Not Found")
      :unauthorized -> error_response(conn, :unauthorized, "Unauthorized")
    end
  end

  defp proxy_with_auth(conn, channel, rest) do
    with {:ok, auth_header} <- resolve_sink_auth(channel),
         {:ok, snapshot} <- Channels.get_or_create_current_snapshot(channel) do
      forward_path = build_forward_path(rest)

      conn
      |> proxy_upstream(channel, snapshot, forward_path, auth_header)
      |> halt()
    else
      {:credential_error, reason} ->
        handle_credential_error(conn, channel, reason)

      {:error, _} ->
        error_response(conn, :internal_server_error, "Internal Server Error")
    end
  end

  defp authenticate_source(conn, channel) do
    methods =
      channel.source_auth_methods
      |> Enum.map(& &1.webhook_auth_method)
      |> Enum.reject(&is_nil/1)

    case methods do
      [] -> :ok
      _ -> check_source_auth(conn, methods)
    end
  end

  defp check_source_auth(conn, auth_methods) do
    cond do
      Auth.valid_key?(conn, auth_methods) or
          Auth.valid_user?(conn, auth_methods) ->
        :ok

      Auth.has_credentials?(conn) ->
        :not_found

      true ->
        :unauthorized
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

  defp proxy_upstream(conn, channel, snapshot, forward_path, auth_header) do
    request_id =
      conn
      |> Plug.Conn.get_resp_header("x-request-id")
      |> List.first()

    outbound_headers = build_outbound_headers(conn, auth_header)

    handler_state = %{
      channel: channel,
      snapshot: snapshot,
      request_id: request_id,
      started_at: DateTime.utc_now(),
      request_path: forward_path,
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
            headers: outbound_headers,
            handler: {Lightning.Channels.Handler, handler_state}
          )

        {result, metadata}
      end
    )
  end

  defp fetch_channel(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Channels.Channel{enabled: true} = channel <-
           Channels.get_channel_with_auth(uuid) do
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

  defp build_proxy_headers(conn) do
    original_host = get_req_header(conn, "host") |> List.first("")
    remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    existing_xff = get_req_header(conn, "x-forwarded-for") |> List.first()

    xff_value =
      if existing_xff, do: "#{existing_xff}, #{remote_ip}", else: remote_ip

    [
      {"x-forwarded-for", xff_value},
      {"x-forwarded-host", original_host},
      {"x-forwarded-proto", to_string(conn.scheme)}
    ]
  end

  defp build_outbound_headers(conn, auth_header) do
    proxy_headers = build_proxy_headers(conn)

    conn.req_headers
    |> Kernel.++(proxy_headers)
    |> maybe_set_auth(auth_header)
  end

  defp maybe_set_auth(headers, nil), do: headers

  defp maybe_set_auth(headers, value) do
    headers
    |> Enum.reject(fn {k, _} -> String.downcase(k) == "authorization" end)
    |> Kernel.++([{"authorization", value}])
  end

  defp resolve_sink_auth(channel) do
    case channel.sink_auth_methods do
      [] ->
        {:ok, nil}

      [%{project_credential: %{credential: credential}}] ->
        with {:ok, body} <-
               Lightning.Credentials.resolve_credential_body(
                 credential,
                 "main"
               ),
             {:ok, header} <-
               Channels.SinkAuth.build_auth_header(credential.schema, body) do
          {:ok, header}
        else
          {:error, reason} -> {:credential_error, reason}
        end
    end
  end

  defp handle_credential_error(conn, channel, reason) do
    error_message = classify_credential_error(reason)

    case Channels.get_or_create_current_snapshot(channel) do
      {:ok, snapshot} ->
        record_credential_error(conn, channel, snapshot, error_message)

      {:error, _} ->
        Logger.error(
          "Failed to create snapshot for credential error on channel #{channel.id}"
        )

        error_response(conn, :bad_gateway, "Bad Gateway")
    end
  end

  defp record_credential_error(conn, channel, snapshot, error_message) do
    now = DateTime.utc_now()

    request_id =
      conn
      |> Plug.Conn.get_resp_header("x-request-id")
      |> List.first()

    with {:ok, channel_request} <-
           %ChannelRequest{}
           |> ChannelRequest.changeset(%{
             channel_id: channel.id,
             channel_snapshot_id: snapshot.id,
             request_id: request_id,
             client_identity: get_client_identity(conn),
             state: :error,
             started_at: now,
             completed_at: now
           })
           |> Repo.insert(),
         {:ok, _event} <-
           %ChannelEvent{}
           |> ChannelEvent.changeset(%{
             channel_request_id: channel_request.id,
             type: :error,
             request_method: conn.method,
             request_path: conn.request_path,
             error_message: error_message
           })
           |> Repo.insert() do
      :ok
    else
      {:error, changeset} ->
        Logger.warning(
          "Failed to record credential error for channel #{channel.id}: " <>
            "#{inspect(changeset.errors)}"
        )
    end

    error_response(conn, :bad_gateway, "Bad Gateway")
  end

  defp error_response(conn, status, message) do
    conn |> put_status(status) |> json(%{"error" => message}) |> halt()
  end

  defp classify_credential_error(:environment_not_found),
    do: "credential_environment_not_found"

  defp classify_credential_error(:no_auth_fields),
    do: "credential_missing_auth_fields"

  defp classify_credential_error({:unsupported_schema, schema}),
    do: "unsupported_credential_schema:#{schema}"

  defp classify_credential_error({:oauth_refresh_failed, _}),
    do: "oauth_refresh_failed"

  defp classify_credential_error(other),
    do: "credential_error:#{inspect(other)}"
end
