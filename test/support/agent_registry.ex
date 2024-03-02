defmodule AgentRegistry do
  @moduledoc """
  A registry that can be used in tests to register processes and
  associate them with a common Agent.

  This is useful when testing procceses that are started during a test, for
  example LiveView processes.

  ## Example

      defmodule MyTest do
        use ExUnit.Case, async: true

        setup do
          AgentRegistry.start_link()
          AgentRegistry.register()
          :ok
        end

        test "something" do
          {:ok, pid} = MyProcess.start_link()
          AgentRegistry.register(pid)
          AgentRegistry.put(:something)

          task =
            Task.async(fn ->
              Process.sleep(100)
              AgentRegistry.get()
            end)

          AgentRegistry.register(task.pid)

          AgentRegistry.put(1)

          assert Task.await(task) == 1
        end
      end

  This becomes an important pattern when you want your tests to stay asynchronus
  but also to be able to stub and replace data that is used in the processes.
  """
  use GenServer

  @impl true
  def init(_opts \\ []) do
    names = %{}
    refs = %{}
    {:ok, {names, refs}}
  end

  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      :ok,
      Keyword.merge([name: __MODULE__], opts)
    )
  end

  @impl true
  def handle_call({:lookup, pid}, _from, state) do
    {pids, _} = state
    {:reply, Map.fetch(pids, pid), state}
  end

  @impl true
  def handle_call({:create, parent_pid, other_pid}, _from, {pids, refs}) do
    case Map.get(pids, parent_pid) do
      nil ->
        {:reply, {:error, :no_parent_registered}, {pids, refs}}

      agent ->
        ref = Process.monitor(other_pid)
        refs = Map.put(refs, ref, other_pid)
        pids = Map.put(pids, other_pid, agent)
        {:reply, :ok, {pids, refs}}
    end
  end

  @impl true
  def handle_call({:create, pid}, _from, {pids, refs}) do
    if Map.has_key?(pids, pid) do
      {:reply, {:error, :already_registered}, {pids, refs}}
    else
      {:ok, bucket} = Agent.start_link(fn -> %{} end)
      ref = Process.monitor(bucket)
      refs = Map.put(refs, ref, pid)
      pids = Map.put(pids, pid, bucket)
      {:reply, :ok, {pids, refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {pids, refs}) do
    {pid, refs} = Map.pop(refs, ref)
    pids = Map.delete(pids, pid)
    {:noreply, {pids, refs}}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.debug("Unexpected message in AgentRegistry: #{inspect(msg)}")
    {:noreply, state}
  end

  @doc """
  Registers a process with the registry.

  If adding a process that is not the current process, the agent associated with
  the current process will be associated with the given process.
  """
  def register(pid \\ nil) do
    pid = pid || self()

    if pid == self() do
      GenServer.call(__MODULE__, {:create, pid})
    else
      GenServer.call(__MODULE__, {:create, self(), pid})
    end
  end

  @spec get(atom(), any()) :: any()
  def get(key, default \\ nil)

  def get(key, default) when is_atom(key) do
    # TODO: use Process.get(:"$ancestors") to find the parent pid
    # this would allow us to _not_ have to register child processes and
    # instead just 'attach' the parent process.
    GenServer.call(__MODULE__, {:lookup, self()})
    |> case do
      {:ok, pid} ->
        Agent.get(pid, &Map.get(&1, key, default))

      :error ->
        :error
    end
  end

  def put(key, value) do
    GenServer.call(__MODULE__, {:lookup, self()})
    |> case do
      {:ok, pid} -> Agent.update(pid, &Map.put(&1, key, value))
      :error -> nil
    end
  end
end
