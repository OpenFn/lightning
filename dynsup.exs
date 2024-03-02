defmodule CLIWorker do
  use GenServer
  @default_name :cli_worker
  @process_limit 4

  @impl true
  def init(_opts \\ []) do
    # telemetry
    {:ok, task_sup} =
      Task.Supervisor.start_link(max_children: @process_limit * 2)

    {:ok, %{task_sup: task_sup, max_tasks: @process_limit}}
  end

  @impl true
  def handle_call(:checkout, _from, state) do
    spec_count =
      Supervisor.count_children(state.task_sup)
      |> IO.inspect()
      |> Map.get(:specs)
      |> IO.inspect(label: "count_children checkout")

    if spec_count >= state.max_tasks do
      {:reply, {:error, :too_many_processes}, state}
    else
      {:reply, {:ok, state.task_sup}, state}
    end
  end

  @impl true
  def handle_cast(:checkin, state) do
    Supervisor.count_children(state.task_sup)
    |> Map.get(:specs)
    |> IO.inspect(label: "count_children checkin")

    # telemetry
    {:noreply, state}
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @default_name)
  end

  # TODO: abstract the "run_command", this will allow reuse on other functions
  def execute(cmd) do
    GenServer.call(@default_name, :checkout)
    |> case do
      {:ok, task_sup} ->
        %Task{ref: task_ref} =
          Task.Supervisor.async_nolink(task_sup, fn -> run_command(cmd) end)

        receive do
          {^task_ref, res} ->
            Process.demonitor(task_ref, [:flush])
            # By sending another message to the server, we create a tiny buffer
            # that slows the calls to `:checkout` which in turn gives us a tiny
            # gap between `count_children` calls.
            GenServer.cast(@default_name, :checkin)

            res

          {:DOWN, ^task_ref, :process, _pid, reason} ->
            GenServer.cast(@default_name, :checkin)
            {:error, reason}

          res ->
            {:other, res}
        end

      any ->
        any
    end
  end

  defp run_command(cmd) do
    if cmd |> String.contains?("sleep 3") do
      raise "ERROR"
    end

    case System.cmd("sh", ["-c", cmd]) do
      {result, 0} -> result
      {_, code} -> raise "Command failed with exit code #{code}"
    end
  end
end

{:ok, sup} = DynamicSupervisor.start_link(name: :fake_superviser)

worker = DynamicSupervisor.start_child(sup, {CLIWorker, [name: :cli_worker]})
Process.whereis(:cli_worker) |> IO.inspect()
IO.inspect(worker)

Enum.map(1..10, fn i ->
  Task.async(fn ->
    CLIWorker.execute("sleep #{i}; echo #{i}")
    # |> IO.inspect(label: "execute result")
    # |> IO.inspect(label: i)
  end)
end)
|> Enum.map(&Task.await(&1, 12_000))
# |> Task.await_many(12_000)
|> IO.inspect()

DynamicSupervisor.stop(sup) |> IO.inspect(label: "stop sup")
# {:ok, pid} = MyProcessManager.start_link()
# # :sys.trace(pid, true)

# MyProcessManager.test()

# ProcessManager.run_shell_command("sleep 1") |> IO.inspect()
# ProcessManager.run_shell_command("sleep 1") |> IO.inspect()
# ProcessManager.run_shell_command("sleep 1") |> IO.inspect()
# ProcessManager.run_shell_command("sleep 1") |> IO.inspect()
