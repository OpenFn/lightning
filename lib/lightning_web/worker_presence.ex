defmodule LightningWeb.WorkerPresence do
  @moduledoc """
  Handles worker presence tracking for connected workers.

  This module leverages Phoenix.Presence to track worker connections,
  allowing the system to dynamically calculate available worker capacity.
  """
  use Phoenix.Presence,
    otp_app: :lightning,
    pubsub_server: Lightning.PubSub

  @worker_topic "workers:presence"

  @doc """
  Tracks a worker's presence when they connect.

  ## Parameters

    - `pid`: The process identifier for the worker's channel.
    - `worker_id`: A unique identifier for the worker.
    - `capacity`: The number of concurrent runs this worker can handle.

  ## Examples

      iex> LightningWeb.WorkerPresence.track_worker(self(), "worker-123", 5)
      {:ok, _ref}

  """
  def track_worker(pid, worker_id, capacity) do
    track(pid, @worker_topic, worker_id, %{
      capacity: capacity,
      joined_at: System.system_time(:microsecond)
    })
  end

  @doc """
  Calculates the total worker capacity across all connected workers.

  Returns the sum of all worker capacities currently tracked in Presence.

  ## Examples

      iex> LightningWeb.WorkerPresence.total_worker_capacity()
      10

  """
  def total_worker_capacity do
    @worker_topic
    |> list()
    |> Enum.reduce(0, fn {_worker_id, %{metas: metas}}, acc ->
      # Sum up capacity from all metas for this worker
      worker_capacity =
        Enum.reduce(metas, 0, fn meta, sum -> sum + meta.capacity end)

      acc + worker_capacity
    end)
  end
end
