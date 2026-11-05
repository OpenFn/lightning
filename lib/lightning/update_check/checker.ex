defmodule Lightning.UpdateCheck.Checker do
  @moduledoc """
  Runs `Lightning.UpdateCheck.check/2` on a timer and keeps the last good
  result for `status/1`.

  Each check runs in a task so `status/1` answers immediately while a check is
  in flight. A failed check is logged and the previous result is kept. Every
  node runs its own checker; that is a handful of requests a day per node.
  """

  use GenServer

  require Logger

  @status_timeout 1_000
  @check_now_timeout 30_000

  @doc """
  Starts the checker.

  Options:

  - `:name` - registered name, defaults to `#{inspect(__MODULE__)}`; pass
    `nil` for an anonymous process
  - `:config` - the `config :lightning, :update_check` keyword list, passed
    to `Lightning.UpdateCheck.check/2`; required unless `:check_fun` is given
  - `:check_fun` - 0-arity function returning `{:ok, status} | {:error, _}`,
    defaults to checking with `:config`
  - `:interval` - milliseconds between checks
  - `:initial_delay` - milliseconds before the first check
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    _ = Keyword.fetch!(opts, :interval)

    if name,
      do: GenServer.start_link(__MODULE__, opts, name: name),
      else: GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  The last good result, or `nil` when there is none or the checker isn't
  running.
  """
  @spec status(GenServer.server()) :: Lightning.UpdateCheck.status() | nil
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status, @status_timeout)
  catch
    :exit, _reason -> nil
  end

  @doc """
  Runs a check, or joins the one in flight, and waits for its result.
  """
  @spec check_now(GenServer.server()) ::
          {:ok, Lightning.UpdateCheck.status()} | {:error, term()}
  def check_now(server \\ __MODULE__) do
    GenServer.call(server, :check_now, @check_now_timeout)
  catch
    :exit, {:noproc, _} -> {:error, :disabled}
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @impl true
  def init(opts) do
    # Checks run unlinked under this supervisor, so a check that dies, for any
    # reason, arrives as a :DOWN rather than taking the checker with it.
    {:ok, task_supervisor} = Task.Supervisor.start_link()

    state = %{
      task_supervisor: task_supervisor,
      check_fun:
        Keyword.get_lazy(opts, :check_fun, fn -> default_check(opts) end),
      interval: Keyword.fetch!(opts, :interval),
      status: nil,
      task: nil,
      waiters: []
    }

    Process.send_after(self(), :check, Keyword.get(opts, :initial_delay, 0))

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:check_now, from, state) do
    {:noreply, state |> start_check() |> Map.update!(:waiters, &[from | &1])}
  end

  @impl true
  def handle_info(:check, state) do
    Process.send_after(self(), :check, state.interval)
    {:noreply, start_check(state)}
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_check(state, result)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{task: %Task{ref: ref}} = state
      ) do
    {:noreply, finish_check(state, {:error, {:exit, reason}})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp default_check(opts) do
    config = Keyword.fetch!(opts, :config)
    fn -> Lightning.UpdateCheck.check(config) end
  end

  defp start_check(%{task: nil} = state) do
    check_fun = state.check_fun

    # Catching here turns a failed check into an ordinary error result instead
    # of a task crash report.
    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        try do
          check_fun.()
        rescue
          error -> {:error, error}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    %{state | task: task}
  end

  defp start_check(state), do: state

  defp finish_check(state, result) do
    status =
      case result do
        {:ok, status} ->
          status

        {:error, reason} ->
          Logger.warning("Update check failed: #{inspect(reason)}")
          state.status
      end

    Enum.each(state.waiters, &GenServer.reply(&1, result))

    %{state | status: status, task: nil, waiters: []}
  end
end
