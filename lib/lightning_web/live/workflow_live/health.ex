defmodule LightningWeb.WorkflowLive.Health do
  @moduledoc """
  Workflow health page: a summary of a single workflow's work orders over the
  window the reader picks.
  """
  use LightningWeb, :live_view

  alias Lightning.Workflows
  alias Lightning.WorkOrders
  alias Lightning.WorkOrders.Events

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :ensure_workflow_belongs_to_project}

  # At most one refresh per window, with the first change in a quiet period
  # pushed straight away: during an incident the first failure should be on
  # screen now, not half a minute later. A burst collapses into one more push
  # when the window closes.
  @refresh_window :timer.seconds(30)

  @final_states Lightning.WorkOrder.final_states()

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_menu_item: :overview, refresh: :idle)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    workflow = Workflows.get_workflow!(id)

    if connected?(socket), do: WorkOrders.subscribe(workflow)

    {:noreply,
     socket
     |> assign(:workflow, workflow)
     |> assign(:page_title, workflow.name)}
  end

  @impl true
  def handle_info(
        %Events.WorkOrderUpdated{work_order: %{state: state}},
        socket
      )
      when state in @final_states do
    {:noreply, throttled_refresh(socket)}
  end

  # A work order that started or was retried has nothing this page draws — it
  # counts final states only.
  def handle_info(%Events.WorkOrderUpdated{}, socket), do: {:noreply, socket}

  def handle_info(
        :refresh_window_closed,
        %{assigns: %{refresh: :dirty}} = socket
      ) do
    {:noreply, socket |> assign(refresh: :cooling) |> push_refresh()}
  end

  def handle_info(:refresh_window_closed, socket) do
    {:noreply, assign(socket, refresh: :idle)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp throttled_refresh(%{assigns: %{refresh: :idle}} = socket) do
    socket |> assign(refresh: :cooling) |> push_refresh()
  end

  defp throttled_refresh(socket), do: assign(socket, refresh: :dirty)

  defp push_refresh(socket) do
    # The cache outlives the change that just landed, so the refresh this
    # triggers would otherwise be answered from a value computed before it.
    Workflows.Stats.invalidate(socket.assigns.workflow.id)

    Process.send_after(self(), :refresh_window_closed, @refresh_window)

    push_event(socket, "health:changed", %{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:breadcrumbs>
            <LayoutComponents.breadcrumbs>
              <LayoutComponents.breadcrumb_project_picker
                project={@project}
                label={@project_label}
              />
              <LayoutComponents.breadcrumb>
                <:label>{@workflow.name}</:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
        </LayoutComponents.header>
      </:header>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div
          id="workflow-health"
          phx-hook="ReactComponent"
          phx-update="ignore"
          data-react-name="WorkflowHealth"
          data-react-file={~p"/assets/js/health/WorkflowHealth.js"}
          data-workflow-id={@workflow.id}
          data-project-id={@project.id}
          data-workflow-name={@workflow.name}
        >
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end
end
