defmodule Lightning.Channels.Handler do
  @moduledoc """
  Weir handler that persists every proxied Channel request.

  ## Lifecycle

  Weir invokes three callbacks during the proxy lifecycle:

  1. `handle_request_started` — creates a `ChannelRequest` record
     synchronously. If the insert fails, the request is rejected with 503.

  2. `handle_response_started` — captures TTFB and response headers into
     handler state. **May not be called** — see below.

  3. `handle_response_finished` — spawns an async task to create a
     `ChannelEvent` and update the `ChannelRequest` state.

  ## Skipped `handle_response_started`

  `handle_response_started` fires when the first response bytes arrive from
  the upstream (TTFB). If the upstream never sends a response, the callback
  is skipped entirely and `handle_response_finished` receives handler state
  from `handle_request_started` only — without `ttfb_us`, `response_status`,
  or `response_headers`.

  This happens when:

  - DNS resolution fails (`:nxdomain`)
  - The upstream refuses the connection (`:econnrefused`)
  - The host or network is unreachable (`:ehostunreach`, `:enetunreach`)
  - The connection times out before any response (`:connect_timeout`)
  - The response times out before headers arrive (`:timeout`)
  - TLS handshake fails

  All fields derived from `handle_response_started` are accessed via
  `Map.get/2` with `nil` fallbacks, so this is safe. The `classify_error/1`
  function translates known Weir error shapes into stable string identifiers
  for persistence.
  """

  use Weir.Handler

  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Repo

  require Logger

  @redacted_headers ~w(authorization x-api-key)

  @known_transport_errors ~w(
    nxdomain econnrefused ehostunreach enetunreach
    closed econnreset econnaborted epipe
  )a

  @impl true
  def handle_request_started(metadata, state) do
    attrs = %{
      channel_id: state.channel.id,
      channel_snapshot_id: state.snapshot.id,
      request_id: state.request_id,
      client_identity: state.client_identity,
      state: :pending,
      started_at: state.started_at
    }

    case %ChannelRequest{} |> ChannelRequest.changeset(attrs) |> Repo.insert() do
      {:ok, channel_request} ->
        {:ok,
         Map.merge(state, %{
           channel_request: channel_request,
           request_headers: redact_headers(metadata.headers),
           request_method: metadata.method
         })}

      {:error, _changeset} ->
        Logger.warning("Failed to create ChannelRequest for #{state.request_id}")

        {:reject, 503, "Service Unavailable", state}
    end
  end

  @impl true
  def handle_response_started(metadata, state) do
    {:ok,
     Map.merge(state, %{
       ttfb_us: metadata.time_to_first_byte_us,
       response_status: metadata.status,
       response_headers: redact_headers(metadata.headers)
     })}
  end

  @impl true
  def handle_response_finished(result, state) do
    supervisor =
      Map.get(state, :task_supervisor, Lightning.Channels.TaskSupervisor)

    Task.Supervisor.start_child(
      supervisor,
      fn -> persist_completion(result, state) end
    )

    {:ok, state}
  end

  defp persist_completion(result, state) do
    request_state = derive_request_state(result)
    event_type = derive_event_type(result)

    event_attrs = %{
      channel_request_id: state.channel_request.id,
      type: event_type,
      request_method: state.request_method,
      request_path: state.request_path,
      request_headers: encode_headers(state.request_headers),
      request_body_preview: get_in(result, [:request_observation, :preview]),
      request_body_hash: get_in(result, [:request_observation, :hash]),
      response_status: result.status,
      response_headers: encode_headers(Map.get(state, :response_headers)),
      response_body_preview: get_in(result, [:response_observation, :preview]),
      response_body_hash: get_in(result, [:response_observation, :hash]),
      latency_ms: div(result.duration_us, 1000),
      ttfb_ms: state |> Map.get(:ttfb_us) |> maybe_div(1000),
      error_message: if(result.error, do: classify_error(result.error))
    }

    request_update = %{
      state: request_state,
      completed_at: DateTime.utc_now()
    }

    with {:ok, _event} <-
           %ChannelEvent{}
           |> ChannelEvent.changeset(event_attrs)
           |> Repo.insert(),
         {:ok, _request} <-
           state.channel_request
           |> ChannelRequest.changeset(request_update)
           |> Repo.update() do
      :ok
    else
      {:error, changeset} ->
        Logger.warning(
          "Failed to persist channel observation for request " <>
            "#{state.channel_request.request_id}: #{inspect(changeset.errors)}"
        )

        state.channel_request
        |> ChannelRequest.changeset(%{
          state: :error,
          completed_at: DateTime.utc_now()
        })
        |> Repo.update()
    end

    # TODO: This broadcasts even if event insert and fallback update both
    # failed, so subscribers may see a request still in :pending state.
    # Revisit when #4408 uses this for real-time UI updates.
    Lightning.broadcast(
      "channels:#{state.channel.id}",
      {:channel_request_completed, state.channel_request.id}
    )
  end

  defp derive_request_state(result) do
    cond do
      match?({:timeout, _}, result.error) -> :timeout
      result.error != nil -> :error
      result.status in 200..299 -> :success
      result.status in 400..599 -> :failed
      true -> :error
    end
  end

  defp derive_event_type(result) do
    if result.error != nil, do: :error, else: :sink_response
  end

  defp redact_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {key, value} ->
      if String.downcase(key) in @redacted_headers do
        {key, "[REDACTED]"}
      else
        {key, value}
      end
    end)
  end

  defp redact_headers(nil), do: nil

  defp encode_headers(nil), do: nil

  # Encodes as array-of-pairs rather than a map because HTTP allows
  # duplicate header keys (e.g. multiple Set-Cookie headers).
  defp encode_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> [k, v] end)
    |> Jason.encode!()
  end

  defp classify_error({:timeout, :connect_timeout}), do: "connect_timeout"
  defp classify_error({:timeout, :timeout}), do: "response_timeout"
  defp classify_error({:timeout, {:closed, :timeout}}), do: "timeout"

  defp classify_error(%{reason: reason})
       when reason in @known_transport_errors,
       do: Atom.to_string(reason)

  defp classify_error(error), do: inspect(error)

  defp maybe_div(nil, _), do: nil
  defp maybe_div(us, divisor), do: div(us, divisor)
end
