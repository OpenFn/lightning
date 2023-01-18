defmodule Lightning.Backend.Mnesia do
  @moduledoc """
  An Mnesia backend for Hammer

  The public API of this module is used by Hammer to store information about
  rate-limit 'buckets'. A bucket is identified by a `key`, which is a tuple
  `{bucket_number, id}`. The essential schema of a bucket is:
  `{key, count, created_at, updated_at}`, although backends are free to
  store and retrieve this data in whichever way they wish.

  Use `start` or `start_link` to start the server:

      {:ok, pid} = Hammer.Backend.Mnesia.start_link(args)

  `args` is a keyword list:
  - `expiry_ms`: (integer) time in ms before a bucket is auto-deleted,
    should be larger than the expected largest size/duration of a bucket
  - `cleanup_interval_ms`: (integer) time between cleanup runs,
  - `table_name`: (atom) table name to use, defaults to `:__hammer_backend_mnesia`,

  Example:

      Hammer.Backend.Mnesia.start_link(
        expiry_ms: 1000 * 60 * 60,
        cleanup_interval_ms: 1000 * 60 * 10
      )
  """

  @behaviour Hammer.Backend

  use GenServer

  alias :mnesia, as: Mnesia
  alias Hammer.Utils

  @type bucket_key :: {bucket :: integer, id :: String.t()}
  @type bucket_info ::
          {key :: bucket_key, count :: integer, created :: integer,
           updated :: integer}

  @default_table_name :ligthning_backend_mnesia
  @table_attributes [:key, :bucket, :id, :count, :created, :updated]
  @table_indices [:id, :updated]
  @table_type :set

  ## Public API

  def create_mnesia_table do

    create_mnesia_table(@default_table_name, [])
  end

  def create_mnesia_table(table_name) when is_atom(table_name) do
    create_mnesia_table(table_name, [])
  end

  def create_mnesia_table(opts) when is_list(opts) do
    IO.inspect("MNSEAI")
    create_mnesia_table(@default_table_name, opts)
  end

  @doc """
  Create the mnesia table.

  - `table_name`: atom name of table, defaults to :__hammer_backend_mnesia
  - `opt`: keyword list of options to `:mnesia.create_table/2`,
  all options are suppoted except
  `:access_mode`, `:attributes`, `:index`, `:type`, and `:record_name`,
  which are not configurable.
  """
  def create_mnesia_table(table_name, opts) do
    opts =
      opts
      |> Keyword.put(:access_mode, :read_write)
      |> Keyword.put(:attributes, @table_attributes)
      |> Keyword.put(:index, @table_indices)
      |> Keyword.put(:type, @table_type)
      |> Keyword.put(:record_name, table_name)

    Mnesia.create_table(table_name, opts)
  end

  def start do
    start([])
  end

  def start(args) do
    GenServer.start(__MODULE__, args)
  end

  def start_link do
    start_link([])
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Record a hit in the bucket identified by `key`
  """
  @spec count_hit(
          pid :: pid(),
          key :: bucket_key,
          now :: integer
        ) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
  def count_hit(pid, key, now) do
    GenServer.call(pid, {:count_hit, key, now, 1})
  end

  @doc """
  Record a hit in the bucket identified by `key`, with a custom increment
  """
  @spec count_hit(
          pid :: pid(),
          key :: bucket_key,
          now :: integer,
          increment :: integer
        ) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
  def count_hit(pid, key, now, increment) do
    GenServer.call(pid, {:count_hit, key, now, increment})
  end

  @doc """
  Retrieve information about the bucket identified by `key`
  """
  @spec get_bucket(
          pid :: pid(),
          key :: bucket_key
        ) ::
          {:ok, info :: bucket_info}
          | {:ok, nil}
          | {:error, reason :: any}
  def get_bucket(pid, key) do
    GenServer.call(pid, {:get_bucket, key})
  end

  @doc """
  Delete all buckets associated with `id`.
  """
  @spec delete_buckets(
          pid :: pid(),
          id :: String.t()
        ) ::
          {:ok, count_deleted :: integer}
          | {:error, reason :: any}
  def delete_buckets(pid, id) do
    GenServer.call(pid, {:delete_buckets, id})
  end

  ## GenServer Callbacks

  def init(args) do
    table_name = Keyword.get(args, :table_name, @default_table_name)
    expiry_ms = Keyword.get(args, :expiry_ms)
    cleanup_interval_ms = Keyword.get(args, :cleanup_interval_ms)

    if !expiry_ms do
      raise RuntimeError, "Missing required config: expiry_ms"
    end

    if !cleanup_interval_ms do
      raise RuntimeError, "Missing required config: cleanup_interval_ms"
    end

    prune_process_key = :__hammer_backend_mnesia_prune

    if !Process.whereis(prune_process_key) do
      :timer.send_interval(cleanup_interval_ms, :prune)
      Process.register(self(), prune_process_key)
    end

    state = %{
      table_name: table_name,
      expiry_ms: expiry_ms
    }

    {:ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:count_hit, key, now, increment}, _from, %{} = state) do
    %{table_name: table_name} = state
    {bucket, id} = key

    t_fn = fn ->
      case Mnesia.read(table_name, key) do
        [] ->
          # Insert
          Mnesia.write({table_name, key, bucket, id, increment, now, now})
          {:ok, increment}

        [{^table_name, _, _, _, n, created, _}] ->
          # Update
          Mnesia.write(
            {table_name, key, bucket, id, n + increment, created, now}
          )

          {:ok, n + increment}
      end
    end

    run_transaction(t_fn, state)
  end

  def handle_call({:get_bucket, key}, _from, %{} = state) do
    %{table_name: table_name} = state

    t_fn = fn ->
      case Mnesia.read(table_name, key) do
        [] ->
          {:ok, nil}

        [{_, _, _, _, n, created, updated}] ->
          {:ok, {key, n, created, updated}}
      end
    end

    run_transaction(t_fn, state)
  end

  def handle_call({:delete_buckets, id}, _from, %{} = state) do
    %{table_name: table_name} = state

    t_fn = fn ->
      match = {:_, :"$1", :_, :"$2", :_, :_, :_}
      filter = [{:==, :"$2", id}]
      project = [:"$1"]

      keys_to_delete =
        Mnesia.select(table_name, [
          {match, filter, project}
        ])

      Enum.each(
        keys_to_delete,
        fn k ->
          Mnesia.delete(table_name, k, :write)
        end
      )

      {:ok, Enum.count(keys_to_delete)}
    end

    run_transaction(t_fn, state)
  end

  def handle_info(:prune, state) do
    %{table_name: table_name, expiry_ms: expiry_ms} = state
    now = Utils.timestamp()
    expire_before = now - expiry_ms

    t_fn = fn ->
      match = {:_, :"$1", :_, :_, :_, :_, :"$2"}
      filter = [{:<, :"$2", expire_before}]
      project = [:"$1"]

      keys_to_delete =
        Mnesia.select(table_name, [
          {match, filter, project}
        ])

      Enum.each(
        keys_to_delete,
        fn k ->
          Mnesia.delete(table_name, k, :write)
        end
      )
    end

    Process.spawn(
      fn ->
        Mnesia.transaction(t_fn)
      end,
      []
    )

    {:noreply, state}
  end

  defp run_transaction(t_fn, state) do
    case Mnesia.transaction(t_fn) do
      {:atomic, result} ->
        {:reply, result, state}

      {:aborted, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
