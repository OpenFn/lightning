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

  @type worker :: %{
          id: String.t(),
          capacity: non_neg_integer(),
          joined_at: integer(),
          worker_version: String.t() | nil,
          api_version: String.t() | nil
        }

  @doc """
  The topic presence diffs are broadcast on. Subscribe to it on
  `Lightning.PubSub` to hear when workers connect and disconnect.
  """
  def topic, do: @worker_topic

  @doc """
  Tracks a worker's presence when they connect.

  ## Parameters

    - `pid`: The process identifier for the worker's channel.
    - `worker_id`: A unique identifier for the worker.
    - `capacity`: The number of concurrent runs this worker can handle.
    - `opts`: `:worker_version` and `:api_version`, as the worker reported
      them when it connected.

  ## Examples

      iex> LightningWeb.WorkerPresence.track_worker(self(), "worker-123", 5)
      {:ok, _ref}

  """
  def track_worker(pid, worker_id, capacity, opts \\ []) do
    track(pid, @worker_topic, worker_id, %{
      capacity: capacity,
      joined_at: System.system_time(:microsecond),
      worker_version: opts[:worker_version],
      api_version: opts[:api_version]
    })
  end

  @doc """
  Lists every connected worker across the cluster.

  Versions are `nil` for workers that didn't report them, and for workers
  tracked by a node running an older release.
  """
  @spec list_workers() :: [worker()]
  def list_workers do
    @worker_topic
    |> list()
    |> Enum.flat_map(fn {worker_id, %{metas: metas}} ->
      Enum.map(metas, fn meta ->
        %{
          id: worker_id,
          capacity: meta.capacity,
          joined_at: meta.joined_at,
          worker_version: Map.get(meta, :worker_version),
          api_version: Map.get(meta, :api_version)
        }
      end)
    end)
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
