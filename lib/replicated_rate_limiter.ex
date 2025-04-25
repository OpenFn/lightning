defmodule ReplicatedRateLimiter do
  @moduledoc """
  __using__/1 will inject:

  - `ReplicatedRateLimiter.TokenBucket` - your ETS/CRDT sync server
  - `start_link/1` & `child_spec/1` - to supervise both
  - `allow?/4` - your public rate‑limit check

  Options:

  - `:crdt_name`   - atom name for your AWLWWMap
  - `:ets_table`   - atom for your ETS cache
  - `:default_capacity` - default bucket size
  - `:default_refill` - default tokens/sec
  """

  defmacro __using__(opts) do
    crdt_name =
      Keyword.get(opts, :crdt_name)

    ets_table =
      Keyword.get(opts, :ets_table)

    default_capacity = Keyword.get(opts, :default_capacity, 100)
    default_refill = Keyword.get(opts, :default_refill, 10)

    quote do
      use Supervisor
      alias DeltaCrdt
      require Logger

      default_name_prefix =
        __MODULE__
        |> Module.split()
        |> Enum.join()
        |> String.replace(~r/(?<!^)([A-Z])/, "_\\g{1}")
        |> String.downcase()

      @crdt_name unquote(crdt_name) ||
                   (Macro.escape(default_name_prefix) <> "_crdt")
                   |> String.to_atom()

      @ets_table unquote(ets_table) ||
                   (Macro.escape(default_name_prefix) <> "_ets")
                   |> String.to_atom()

      @cluster_name (Macro.escape(default_name_prefix) <> "_cluster")
                    |> String.to_atom()

      @default_capacity unquote(default_capacity)
      @default_refill unquote(default_refill)

      @doc """
      Same as TokenBucket.allow?/4, but with a default capacity and refill rate.
      """
      def allow?(
            key,
            capacity \\ @default_capacity,
            refill_rate \\ @default_refill,
            cost \\ 1
          ) do
        ReplicatedRateLimiter.TokenBucket.allow?(
          [crdt_name: @crdt_name, ets_table: @ets_table],
          key,
          capacity,
          refill_rate,
          cost
        )
      end

      def inspect(bucket) do
        ReplicatedRateLimiter.TokenBucket.inspect(
          [crdt_name: @crdt_name, ets_table: @ets_table],
          bucket
        )
      end

      def config do
        [crdt_name: @crdt_name, ets_table: @ets_table]
      end

      @doc false
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(opts \\ []) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        children = [
          {ReplicatedRateLimiter.TokenBucket,
           [crdt_name: @crdt_name, ets_table: @ets_table]},
          {CrdtCluster, [crdt: @crdt_name, name: @cluster_name]}
        ]

        Supervisor.init(children, strategy: :one_for_one) |> IO.inspect()
      end

      # Supervisor terminate callback to track when it's being stopped
      def terminate(reason, _state) do
        IO.inspect(reason)
        Logger.warning("#{inspect(__MODULE__)} supervisor terminating with reason: #{inspect(reason)}")
        :ok
      end
    end
  end

  defmodule TokenBucket do
    use GenServer
    require Logger
    alias DeltaCrdt

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def allow?(config, bucket, capacity, refill, cost) do
      ets_table = Keyword.get(config, :ets_table)
      crdt_name = Keyword.get(config, :crdt_name)

      now = System.system_time(:second)

      :ets.insert_new(ets_table, {bucket, {capacity, now}})
      [{^bucket, {level, updated}}] = :ets.lookup(ets_table, bucket)

      refilled = trunc((now - updated) * refill)
      current = min(capacity, level + refilled)

      if current >= cost do
        next_level = current - cost
        :ets.insert(ets_table, {bucket, {next_level, now}})

        DeltaCrdt.put(
          crdt_name,
          {bucket, "#{Node.self()}"},
          {next_level, now}
        )

        {:allow, next_level}
      else
        wait_ms = ceil((cost - current) / refill * 1_000) |> round()
        {:deny, wait_ms}
      end
    end

    def inspect(config, bucket) do
      ets_table = Keyword.get(config, :ets_table)

      :ets.lookup(ets_table, bucket)
      |> case do
        [{^bucket, {level, updated}}] ->
          {level, updated}

        [] ->
          :not_found

        _ ->
          :error
      end
    end

    @impl true
    def init(opts) do
      ets_table = Keyword.fetch!(opts, :ets_table)
      crdt_name = Keyword.fetch!(opts, :crdt_name)

      :ets.new(ets_table, [
        :named_table,
        :public,
        read_concurrency: true
      ])

      DeltaCrdt.start_link(DeltaCrdt.AWLWWMap,
        name: crdt_name,
        sync_interval: 100,
        on_diffs: {__MODULE__, :apply_diffs, [opts]}
      )
      |> case do
        {:ok, pid} ->
          {:ok, %{crdt: pid, crdt_name: crdt_name}}

        {:error, {:already_started, pid}} ->
          {:stop, {:already_started, pid}}
      end
    end

    # merge incoming deltas into ETS
    def apply_diffs(config, diffs) when is_list(diffs) do
      Logger.debug("Applying diffs: #{inspect(diffs)}")

      ets_table = Keyword.get(config, :ets_table)
      crdt_name = Keyword.get(config, :crdt_name)

      Task.start(fn ->
        changed_buckets =
          diffs
          |> Enum.map(fn {:add, {key, _node}, _value} -> key end)
          |> Enum.uniq()

        if changed_buckets != [] do
          crdt_map = DeltaCrdt.to_map(crdt_name)
          # %{
          #   {"test", "a@127.0.0.1"} => {9, 1745414954},
          #   {"test", "b@127.0.0.1"} => {9, 1745414927}
          # }

          Enum.reduce(crdt_map, %{}, fn {{bucket, _node}, value}, acc ->
            if bucket in changed_buckets do
              Map.update(acc, bucket, [value], fn existing_values ->
                [value | existing_values]
              end)
            else
              acc
            end
          end)
          |> Enum.each(fn {bucket, values} ->
            :ets.insert(
              ets_table,
              {bucket, Enum.max_by(values, fn {_, v} -> v end)}
            )
          end)
        end
      end)

      :ok
    end

    @impl true
    def terminate(reason, state) do
      IO.inspect(reason)
      Logger.warning("TokenBucket terminating with reason: #{inspect(reason)}, state: #{inspect(state)}")
      :ok
    end
  end
end

defmodule CrdtCluster do
  # Standalone Cluster module that can be used by any CRDT
  @moduledoc false

  use GenServer
  require Logger

  def start_link(opts) do
    crdt_name = Keyword.fetch!(opts, :crdt)
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, {crdt_name, name}, name: name)
  end

  @impl true
  def init(crdt_name) do
    # watch node up/down
    :net_kernel.monitor_nodes(true, node_type: :visible)
    sync_neighbours(crdt_name)
    {:ok, %{crdt_name: crdt_name}}
  end

  @impl true
  def handle_info({:nodeup, _n, _}, state) do
    sync_neighbours(state.crdt_name)
    {:noreply, state}
  end

  def handle_info({:nodedown, _n, _}, state) do
    sync_neighbours(state.crdt_name)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    Logger.warning("CrdtCluster terminating with reason: #{inspect(reason)}, state: #{inspect(state)}")
    :ok
  end

  defp sync_neighbours(crdt_name) do
    peers = Node.list()
    neighbours = Enum.map(peers, &{crdt_name, &1})

    Logger.debug(
      "CRDT neighbours for #{inspect(crdt_name)}: #{inspect(neighbours)}"
    )

    DeltaCrdt.set_neighbours(crdt_name, neighbours)
  end
end
