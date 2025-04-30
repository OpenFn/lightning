defmodule Lightning.WebhookRateLimiter do
  @moduledoc false
  use GenServer

  @capacity 10
  @refill_per_sec 2

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
      start: {__MODULE__, :start_link, [name]},
      shutdown: 10_000,
      restart: :transient
    }
  end

  def start_link(name) do
    with {:error, {:already_started, pid}} <-
           GenServer.start_link(__MODULE__, [], name: via_tuple(name)) do
      Logger.info("already started at #{inspect(pid)}, returning :ignore")
      :ignore
    end
  end

  @impl true
  def init([]) do
    Process.flag(:trap_exit, true)

    {:ok, %{table: :ets.new(:table, [:set])}}
  end

  def check_rate(bucket, cost \\ 1, name \\ __MODULE__) do
    name
    |> via_tuple()
    |> GenServer.call({:check_rate, bucket, cost})
  end

  def inspect_table(name \\ __MODULE__) do
    name
    |> via_tuple()
    |> GenServer.call(:inspect_table)
  end

  @impl true
  def handle_call({:check_rate, bucket, cost}, _from, %{table: table} = state) do
    {:reply, do_check_rate(table, bucket, cost), state}
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

  def do_check_rate(table, bucket, cost) do
    now = System.monotonic_time(:millisecond)

    :ets.insert_new(table, {bucket, {@capacity, now}})
    [{^bucket, {level, updated}}] = :ets.lookup(table, bucket)

    refilled = div(now - updated, 1_000) * @refill_per_sec
    current = min(@capacity, level + refilled)

    if current >= cost do
      level = current - cost
      :ets.insert(table, {bucket, {level, now}})

      {:allow, level}
    else
      # can retry after 1 second
      {:deny, 1}
    end
  end

  def capacity, do: @capacity
  def refill_per_second, do: @refill_per_sec

  def via_tuple(name),
    do: {:via, Horde.Registry, {Lightning.HordeRegistry, name}}
end
