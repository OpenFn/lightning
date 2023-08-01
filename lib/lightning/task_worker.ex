defmodule Lightning.TaskWorker do
  @moduledoc """
  A TaskWorker with concurrency limits.

  A simple concurrency limiter that wraps `Task.Supervisor`, which already does
  have the ability to specify `max_children`; it throws an error when
  that limit is exceeded.

  To use it, start it like any other process; ideally in your supervision tree.

  ```
    ...,
    {Lightning.TaskWorker, name: :cli_task_worker, max_tasks: 4}
  ```

  **Options**

  - `:max_tasks` Defaults to the number of system schedulers available to the vm.
  """
  use GenServer

  @impl true
  def init(opts \\ []) do
    opts =
      [max_tasks: System.schedulers_online()]
      |> Keyword.merge(opts)

    {:ok, task_sup} = Task.Supervisor.start_link()

    {:ok, %{task_sup: task_sup, max_tasks: opts[:max_tasks], task_count: 0}}
  end

  @impl true
  def handle_call(:checkout, _from, state) do
    if state.task_count >= state.max_tasks do
      {:reply, {:error, :too_many_processes}, state}
    else
      {:reply, {:ok, state.task_sup},
       %{state | task_count: state.task_count + 1}}
    end
  end

  def handle_call(:get_status, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call(:checkin, _from, state) do
    {:reply, :ok, %{state | task_count: state.task_count - 1}}
  end

  def start_link(opts \\ [name: nil]) do
    {opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, opts)
  end

  @spec start_task(worker :: GenServer.name(), (-> any)) ::
          {:error, :too_many_processes} | term()
  def start_task(worker, fun) when is_function(fun, 0) do
    GenServer.call(worker, :checkout)
    |> case do
      {:ok, task_sup} ->
        %Task{ref: task_ref} = Task.Supervisor.async_nolink(task_sup, fun)

        receive do
          {^task_ref, res} ->
            Process.demonitor(task_ref, [:flush])
            # By sending another message to the server, we create a tiny buffer
            # that slows the calls to `:checkout` which in turn gives us a tiny
            # gap between `count_children` calls.
            GenServer.call(worker, :checkin)

            res

          {:DOWN, ^task_ref, :process, _pid, reason} ->
            GenServer.call(worker, :checkin)
            {:error, reason}
        end

      any ->
        any
    end
  end

  def get_status(worker) do
    GenServer.call(worker, :get_status)
  end
end
