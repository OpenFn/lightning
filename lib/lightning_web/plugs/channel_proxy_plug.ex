defmodule LightningWeb.ChannelProxyPlug do
  @moduledoc """
  Reverse proxy plug for channels.

  Authenticates the inbound request against the channel's source auth
  methods, resolves sink credentials, and streams the request upstream
  via `Philter.proxy/2`. Request and response events are recorded as
  `ChannelRequest` / `ChannelEvent` records for auditing.

  ## Request ID

  An `x-request-id` header is forwarded to the sink for end-to-end
  tracing. If the caller provides one it will be used, but
  `Plug.RequestId` requires it to be between 20 and 200 characters —
  shorter or longer values are discarded and a new ID is generated
  automatically.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Lightning.Channels
  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Repo
  alias LightningWeb.Auth

  require Logger

  defmodule SinkRequest do
    @moduledoc false
    @enforce_keys [
      :channel,
      :snapshot,
      :request_id,
      :forward_path,
      :client_identity
    ]
    defstruct [
      :channel,
      :snapshot,
      :request_id,
      :forward_path,
      :client_identity,
      :auth_header
    ]
  end

  defmodule Headers do
    @moduledoc false

    import Plug.Conn, only: [get_req_header: 2]

    alias LightningWeb.ChannelProxyPlug.SinkRequest

    def reject_header(headers, name) do
      downcased = String.downcase(name)
      Enum.reject(headers, fn {k, _} -> String.downcase(k) == downcased end)
    end

    def set_header(headers, _name, nil), do: headers

    def set_header(headers, name, value) do
      headers |> reject_header(name) |> Kernel.++([{name, value}])
    end

    def add_proxy_headers(headers, conn) do
      original_host = get_req_header(conn, "host") |> List.first("")
      remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

      existing_xff = get_req_header(conn, "x-forwarded-for") |> List.first()

      xff_value =
        if existing_xff, do: "#{existing_xff}, #{remote_ip}", else: remote_ip

      headers ++
        [
          {"x-forwarded-for", xff_value},
          {"x-forwarded-host", original_host},
          {"x-forwarded-proto", to_string(conn.scheme)}
        ]
    end

    def build_outbound_headers(conn, %SinkRequest{} = req) do
      conn.req_headers
      |> reject_header("x-request-id")
      |> add_proxy_headers(conn)
      |> set_header("x-request-id", req.request_id)
      |> set_header("authorization", req.auth_header)
    end
  end

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
      req = %SinkRequest{
        channel: channel,
        snapshot: snapshot,
        request_id:
          conn |> Plug.Conn.get_resp_header("x-request-id") |> List.first(),
        forward_path: build_forward_path(rest),
        client_identity: get_client_identity(conn),
        auth_header: auth_header
      }

      conn
      |> proxy_upstream(req)
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

    if methods == [] or
         Auth.valid_key?(conn, methods) or
         Auth.valid_user?(conn, methods) do
      :ok
    else
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

  defp proxy_upstream(conn, %SinkRequest{} = req) do
    outbound_headers = Headers.build_outbound_headers(conn, req)

    handler_state = %{
      channel: req.channel,
      snapshot: req.snapshot,
      request_id: req.request_id,
      started_at: DateTime.utc_now(),
      request_path: req.forward_path,
      client_identity: req.client_identity
    }

    metadata = %{
      channel_id: req.channel.id,
      sink_url: req.channel.sink_url,
      path: req.forward_path
    }

    :telemetry.span(
      [:lightning, :channel_proxy, :upstream],
      metadata,
      fn ->
        result =
          Philter.proxy(conn,
            upstream: String.trim_trailing(req.channel.sink_url, "/"),
            path: req.forward_path,
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

  # --- Sink auth resolution ---

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

  # --- Error handling ---

  defp handle_credential_error(conn, channel, reason) do
    error_message = classify_credential_error(reason)

    case Channels.get_or_create_current_snapshot(channel) do
      {:ok, snapshot} ->
        req = %SinkRequest{
          channel: channel,
          snapshot: snapshot,
          request_id:
            conn
            |> Plug.Conn.get_resp_header("x-request-id")
            |> List.first(),
          forward_path: conn.request_path,
          client_identity: get_client_identity(conn)
        }

        record_credential_error(conn, req, error_message)

      {:error, _} ->
        Logger.error(
          "Failed to create snapshot for credential error on channel #{channel.id}"
        )

        error_response(conn, :bad_gateway, "Bad Gateway")
    end
  end

  defp record_credential_error(conn, %SinkRequest{} = req, error_message) do
    now = DateTime.utc_now()

    with {:ok, channel_request} <-
           %ChannelRequest{}
           |> ChannelRequest.changeset(%{
             channel_id: req.channel.id,
             channel_snapshot_id: req.snapshot.id,
             request_id: req.request_id,
             client_identity: req.client_identity,
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
          "Failed to record credential error for channel #{req.channel.id}: " <>
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

  defp classify_credential_error(:temporary_failure),
    do: "oauth_refresh_failed"

  defp classify_credential_error(:reauthorization_required),
    do: "oauth_reauthorization_required"
end
