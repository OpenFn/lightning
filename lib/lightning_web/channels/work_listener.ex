defmodule LightningWeb.WorkListener do
  @moduledoc """
  Updates workers when there are runs to be executed
  """

  use GenServer

  alias Lightning.WorkOrders

  defmodule State do
    @moduledoc false
    @enforce_keys [:parent_pid]
    defstruct [:debounce_time_ms, :debounce_timer_ref, :parent_pid]
  end

  @debounce_time_ms 500

  def start_link(opts) do
    # debounce_time can be passed as nil
    debounce_time_ms = opts[:debounce_time_ms] || @debounce_time_ms
    parent_pid = Keyword.fetch!(opts, :parent_pid)

    state = %State{debounce_time_ms: debounce_time_ms, parent_pid: parent_pid}

    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    # subscribe to run created events
    WorkOrders.subscribe()

    {:noreply, state}
  end

  @impl true
  def handle_info(:notify_work_available, %State{} = state) do
    send(state.parent_pid, :work_available)

    {:noreply, %{state | debounce_timer_ref: nil}}
  end

  def handle_info(%WorkOrders.Events.RunCreated{}, %State{} = state) do
    {:noreply, maybe_start_debounce_timer(state)}
  end

  def handle_info(_other_events, state) do
    {:noreply, state}
  end

  defp maybe_start_debounce_timer(%State{} = state) do
    if is_nil(state.debounce_timer_ref) do
      {:ok, ref} =
        :timer.send_after(state.debounce_time_ms, self(), :notify_work_available)

      %{state | debounce_timer_ref: ref}
    else
      state
    end
  end
end
