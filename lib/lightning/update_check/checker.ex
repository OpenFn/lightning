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
  - `:check_fun` - 0-arity function returning `{:ok, status} | {:error, _}`,
    defaults to `&Lightning.UpdateCheck.check/0`
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
    state = %{
      check_fun: Keyword.get(opts, :check_fun, &Lightning.UpdateCheck.check/0),
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

  defp start_check(%{task: nil} = state) do
    check_fun = state.check_fun

    # A raise inside a linked task would take the checker down with it.
    task =
      Task.async(fn ->
        try do
          check_fun.()
        rescue
          error -> {:error, error}
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
