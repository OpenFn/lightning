defmodule Lightning.Channels.Handler do
  @moduledoc """
  Weir handler that persists every proxied Channel request.

  Lifecycle:
  - handle_request_started: creates ChannelRequest (sync, aborts on failure)
  - handle_response_started: captures TTFB and response headers
  - handle_response_finished: spawns async task to create ChannelEvent and
    update ChannelRequest state
  """

  use Weir.Handler

  alias Lightning.Channels.{ChannelRequest, ChannelEvent}
  alias Lightning.Repo

  require Logger

  @redacted_headers ~w(authorization x-api-key)

  @impl true
  def handle_request_started(metadata, state) do
    attrs = %{
      channel_id: state.channel.id,
      channel_snapshot_id: state.snapshot.id,
      request_id: metadata.request_id,
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
        Logger.warning(
          "Failed to create ChannelRequest for #{metadata.request_id}"
        )

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
    Task.Supervisor.start_child(
      Lightning.Channels.TaskSupervisor,
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
      error_message: if(result.error, do: inspect(result.error))
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

  defp encode_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> [k, v] end)
    |> Jason.encode!()
  end

  defp maybe_div(nil, _), do: nil
  defp maybe_div(us, divisor), do: div(us, divisor)
end
