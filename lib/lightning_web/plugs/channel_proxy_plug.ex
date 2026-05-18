defmodule LightningWeb.ChannelProxyPlug do
  @moduledoc """
  Reverse proxy plug for channels.

  Authenticates the inbound request against the channel's client auth
  methods, resolves destination credentials, and streams the request upstream
  via `Philter.proxy/2`. Request and response events are recorded as
  `ChannelRequest` / `ChannelEvent` records for auditing.

  ## Request ID

  An `x-request-id` header is forwarded to the destination for end-to-end
  tracing. If the caller provides one it will be used, but
  `Plug.RequestId` requires it to be between 20 and 200 characters —
  shorter or longer values are discarded and a new ID is generated
  automatically.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Lightning.Channels
  alias Lightning.Channels.PersistencePolicy
  alias LightningWeb.Auth

  require Logger

  defmodule DestinationRequest do
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
      :auth_header,
      :destination_credential_id,
      client_auth_types: []
    ]
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["channels", channel_id | rest]} = conn, _opts) do
    :telemetry.span(
      [:lightning, :channel_proxy, :inbound],
      %{},
      fn -> dispatch(conn, channel_id, rest) end
    )
  end

  def call(conn, _opts), do: conn

  defp dispatch(conn, channel_id, rest) do
    with {:ok, uuid} <- Ecto.UUID.cast(channel_id),
         {:ok, channel} <- fetch_channel_with_telemetry(uuid) do
      conn = handle_resolved(conn, channel, rest)

      {conn,
       %{
         outcome: :resolved,
         status: conn.status,
         channel_id: channel.id,
         project_id: channel.project_id
       }}
    else
      :error ->
        conn = error_response(conn, :not_found, "Not Found")
        {conn, %{outcome: :invalid_uuid, status: conn.status}}

      :not_found ->
        conn = error_response(conn, :not_found, "Not Found")
        {conn, %{outcome: :unknown_channel, status: conn.status}}
    end
  end

  defp handle_resolved(conn, channel, rest) do
    :telemetry.span(
      [:lightning, :channel_proxy, :request],
      %{channel_id: channel.id, project_id: channel.project_id},
      fn ->
        conn = assign(conn, :channel_project_id, channel.project_id)

        result =
          case authenticate_client(conn, channel) do
            {:ok, conn, matched_auth} ->
              forward_request(conn, channel, rest, matched_auth)

            {:unauthorized, conn} ->
              error_response(conn, :unauthorized, "Unauthorized")
          end

        {result,
         %{
           channel_id: channel.id,
           project_id: channel.project_id,
           status: result.status
         }}
      end
    )
  end

  defp forward_request(conn, channel, rest, matched_auth) do
    with {:ok, auth_header} <- resolve_destination_auth(channel),
         {:ok, snapshot} <- Channels.get_or_create_current_snapshot(channel) do
      req = build_destination_request(conn, channel, rest, auth_header, snapshot)

      conn
      |> proxy_upstream(req, matched_auth)
      |> halt()
    else
      {:credential_error, reason} ->
        handle_credential_error(conn, channel, reason)

      {:error, _} ->
        error_response(conn, :internal_server_error, "Internal Server Error")
    end
  end

  defp build_destination_request(conn, channel, rest, auth_header, snapshot) do
    client_auth_types =
      channel.client_webhook_auth_methods
      |> Enum.map(& &1.auth_type)
      |> Enum.uniq()

    %DestinationRequest{
      channel: channel,
      snapshot: snapshot,
      request_id:
        conn |> Plug.Conn.get_resp_header("x-request-id") |> List.first(),
      forward_path: build_forward_path(rest),
      client_identity: get_client_identity(conn),
      auth_header: auth_header,
      client_auth_types: client_auth_types,
      destination_credential_id: destination_credential_id(channel)
    }
  end

  defp destination_credential_id(channel) do
    case channel.destination_auth_method do
      %{project_credential_id: id} -> id
      _ -> nil
    end
  end

  defp authenticate_client(conn, %{client_webhook_auth_methods: []}) do
    {:ok, conn, nil}
  end

  defp authenticate_client(conn, channel) do
    methods = channel.client_webhook_auth_methods

    case find_matching_auth_method(conn, methods) do
      %{} = method -> {:ok, conn, method}
      nil -> {:unauthorized, conn}
    end
  end

  defp find_matching_auth_method(conn, methods) do
    Enum.find(methods, fn method ->
      case method.auth_type do
        :api -> Auth.valid_key?(conn, [method])
        :basic -> Auth.valid_user?(conn, [method])
        _ -> false
      end
    end)
  end

  defp fetch_channel_with_telemetry(uuid) do
    metadata = %{channel_id: uuid}

    :telemetry.span(
      [:lightning, :channel_proxy, :fetch_channel],
      metadata,
      fn ->
        result = fetch_channel(uuid)
        {result, metadata}
      end
    )
  end

  defp proxy_upstream(conn, %DestinationRequest{} = req, matched_auth) do
    handler_state =
      %{
        channel: req.channel,
        snapshot: req.snapshot,
        request_id: req.request_id,
        started_at: DateTime.utc_now(),
        request_path: req.forward_path,
        client_identity: req.client_identity,
        query_string: conn.query_string,
        destination_credential_id: req.destination_credential_id,
        persist_observations:
          PersistencePolicy.persist_observations?(req.channel.project_id)
      }
      |> put_auth_method(matched_auth)

    metadata = %{
      channel_id: req.channel.id,
      destination_url: req.channel.destination_url,
      path: req.forward_path
    }

    :telemetry.span(
      [:lightning, :channel_proxy, :upstream],
      metadata,
      fn ->
        result =
          Philter.proxy(conn,
            upstream: String.trim_trailing(req.channel.destination_url, "/"),
            path: req.forward_path,
            handler: {Lightning.Channels.Handler, handler_state},
            strip_headers: build_strip_headers(req.client_auth_types),
            extra_headers: build_extra_headers(conn, req),
            collect_timing: true
          )

        {result, metadata}
      end
    )
  end

  defp put_auth_method(state, nil), do: state

  defp put_auth_method(state, %{id: id, auth_type: auth_type}) do
    Map.merge(state, %{
      client_webhook_auth_method_id: id,
      client_auth_type: Atom.to_string(auth_type)
    })
  end

  defp build_extra_headers(conn, %DestinationRequest{} = req) do
    xff =
      case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
        [existing] -> "#{existing}, #{:inet.ntoa(conn.remote_ip)}"
        _ -> to_string(:inet.ntoa(conn.remote_ip))
      end

    headers = [
      {"x-forwarded-for", xff},
      {"x-forwarded-host", conn.host},
      {"x-forwarded-proto", to_string(conn.scheme)},
      {"x-request-id", req.request_id}
    ]

    case req.auth_header do
      nil -> headers
      auth -> [{"authorization", auth} | headers]
    end
  end

  defp build_strip_headers(client_auth_types) do
    Enum.flat_map(client_auth_types, fn
      :api -> ["x-api-key"]
      :basic -> ["authorization"]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp fetch_channel(uuid) do
    case Channels.get_channel_with_auth(uuid) do
      %Channels.Channel{enabled: true} = channel -> {:ok, channel}
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

  # --- Destination auth resolution ---

  defp resolve_destination_auth(channel) do
    case channel.destination_auth_method do
      nil ->
        {:ok, nil}

      %{project_credential: %{credential: credential}} ->
        with {:ok, body} <-
               Lightning.Credentials.resolve_credential_body(
                 credential,
                 "main"
               ),
             {:ok, header} <-
               Channels.DestinationAuth.build_auth_header(
                 credential.schema,
                 body
               ) do
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
        now = DateTime.utc_now()

        req_attrs = %{
          channel_id: channel.id,
          channel_snapshot_id: snapshot.id,
          request_id:
            conn
            |> Plug.Conn.get_resp_header("x-request-id")
            |> List.first(),
          client_identity: get_client_identity(conn),
          destination_credential_id: destination_credential_id(channel),
          state: :error,
          started_at: now,
          completed_at: now
        }

        event_attrs = %{
          type: :error,
          request_method: conn.method,
          request_path: conn.request_path,
          error_message: error_message
        }

        Channels.record_destination_credential_error(
          channel,
          req_attrs,
          event_attrs
        )

        error_response(conn, :bad_gateway, "Bad Gateway")

      {:error, _} ->
        Logger.error(
          "Failed to create snapshot for credential error on channel #{channel.id}"
        )

        error_response(conn, :bad_gateway, "Bad Gateway")
    end
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
