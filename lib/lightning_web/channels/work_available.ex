defmodule LightningWeb.WorkAvailable do
  @moduledoc """
  Updates workers in the `worker:queue` channnel when there are runs to be executed
  """

  defmodule State do
    @moduledoc false
    defstruct [:debounce_time_ms, :debounce_timer_ref]
  end

  use GenServer

  alias Lightning.Projects
  alias Lightning.WorkOrders

  @debounce_time_ms 500

  def start_link(opts) do
    {name, _rest} = Keyword.pop(opts, :name, __MODULE__)

    {debounce_time_ms, _rest} =
      Keyword.pop(opts, :debounce_time_ms, @debounce_time_ms)

    state = %State{debounce_time_ms: debounce_time_ms}

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    # subscribe to run created events
    Projects.list_projects()
    |> Enum.each(fn project -> WorkOrders.subscribe(project.id) end)

    # subscribe to project created events
    Projects.subscribe()

    {:noreply, state}
  end

  @impl true
  def handle_info(:notify_work_available, %State{} = state) do
    LightningWeb.Endpoint.broadcast("worker:queue", "work-available", %{})

    {:noreply, %{state | debounce_timer_ref: nil}}
  end

  def handle_info(%Projects.Events.ProjectCreated{project: project}, state) do
    WorkOrders.subscribe(project.id)

    {:noreply, state}
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
