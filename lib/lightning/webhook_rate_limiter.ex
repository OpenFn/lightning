defmodule Lightning.WebhookRateLimiter do
  @moduledoc false
  use GenServer

  require Logger

  def child_spec(opts) do
    {id, name} =
      if name = Keyword.get(opts, :name) do
        {"#{__MODULE__}_#{name}", name}
      else
        {__MODULE__, __MODULE__}
      end

    %{
      id: id,
      start: {__MODULE__, :start_link, [Keyword.put(opts, :name, name)]},
      shutdown: 10_000,
      restart: :transient
    }
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)

    with {:error, {:already_started, pid}} <-
           GenServer.start_link(__MODULE__, opts, name: via_tuple(name)) do
      Logger.info("already started at #{inspect(pid)}, returning :ignore")
      :ignore
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    capacity = Keyword.fetch!(opts, :capacity)
    refill = Keyword.fetch!(opts, :refill_per_second)

    {:ok, %{table: :ets.new(:table, [:set]), capacity: capacity, refill_per_second: refill}}
  end

  def check_rate(bucket, capacity \\ nil, refill \\ nil, name \\ __MODULE__) do
    name
    |> via_tuple()
    |> GenServer.call({:check_rate, bucket, capacity, refill})
  end

  def inspect_table(name \\ __MODULE__) do
    name
    |> via_tuple()
    |> GenServer.call(:inspect_table)
  end

  @impl true
  def handle_call({:check_rate, bucket, capacity, refill}, _from, state) do
    {:reply, do_check_rate(state, bucket, capacity, refill), state}
  end

  @impl true
  def handle_call(:inspect_table, _from, %{table: table} = state) do
    {:reply, :ets.info(table), state}
  end

  @impl true
  def handle_info(
        {:EXIT, _from, {:name_conflict, {_key, _value}, registry, pid}},
        state
      ) do
    Logger.info(
      "Stopping #{inspect({registry, pid})} as it has already started in another node."
    )

    {:stop, :normal, state}
  end

  def do_check_rate(
        %{table: table} = config,
        bucket,
        capacity,
        refill_per_sec
      ) do
    now = System.monotonic_time(:millisecond)
    capacity = capacity || config[:capacity]
    refill_per_sec = refill_per_sec || config[:refill_per_second]

    :ets.insert_new(table, {bucket, {capacity, now}})
    [{^bucket, {level, updated}}] = :ets.lookup(table, bucket)

    refilled = div(now - updated, 1_000) * refill_per_sec
    current = min(capacity, level + refilled)

    if current >= 1 do
      level = current - 1
      :ets.insert(table, {bucket, {level, now}})

      {:allow, level}
    else
      # can retry after 1 second
      {:deny, 1}
    end
  end

  def via_tuple(name),
    do: {:via, Horde.Registry, {Lightning.HordeRegistry, name}}
end
