defmodule LightningWeb.RunLive.WorkOrderComponent do
  @moduledoc """
  Workorder component
  """
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Permissions
  alias Lightning.Invocation
  use Phoenix.Component
  use LightningWeb, :live_component
  import LightningWeb.RunLive.Components

  @impl true
  def update(
        %{work_order: work_order, project: project, current_user: current_user},
        socket
      ) do
    can_rerun_job =
      Permissions.can?(ProjectUsers, :rerun_job, current_user, project)

    {:ok,
     socket
     |> assign(project: project)
     |> assign(can_rerun_job: can_rerun_job)
     |> set_work_order_details(work_order)}
  end

  def update(%{work_order: work_order}, socket) do
    {:ok, socket |> set_work_order_details(work_order)}
  end

  defp set_work_order_details(socket, work_order) do
    last_run = List.last(List.first(work_order.attempts).runs)

    last_run_finished_at =
      case last_run.finished_at do
        nil -> nil
        finished_at -> finished_at |> Calendar.strftime("%c %Z")
      end

    work_order_inserted_at = work_order.inserted_at |> Calendar.strftime("%c %Z")

    socket
    |> assign(
      work_order: work_order,
      attempts: work_order.attempts,
      last_run: last_run,
      last_run_finished_at: last_run_finished_at,
      work_order_inserted_at: work_order_inserted_at,
      workflow_name: work_order.workflow.name || "Untitled"
    )
  end

  @impl true
  def handle_event("toggle_details", %{}, socket) do
    {:noreply, assign(socket, :show_details, !socket.assigns[:show_details])}
  end

  @impl true
  def preload(list_of_assigns) do
    ids = Enum.map(list_of_assigns, & &1.id)

    work_orders =
      Invocation.get_workorders_by_ids(ids)
      |> Invocation.with_attempts()
      |> Lightning.Repo.all()
      |> Enum.into(%{}, fn %{id: id} = wo -> {id, wo} end)

    Enum.map(list_of_assigns, fn assigns ->
      Map.put(assigns, :work_order, work_orders[assigns.id])
    end)
  end

  attr :show_details, :boolean, default: false

  @impl true
  def render(assigns) do
    ~H"""
    <div
      data-entity="work_order"
      class="my-4 grid grid-cols-6 gap-0 rounded-lg bg-white"
    >
      <div class={"my-auto p-4 font-medium text-gray-900 dark:text-white #{unless @show_details, do: "truncate"}"}>
        <input
          type="checkbox"
          class="left-4 top-1/2  h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
          id={@work_order.id}
        />
        <label for={@work_order.id}><%= @workflow_name %></label>
      </div>
      <div class="my-auto p-4"><%= @work_order.reason.type %></div>
      <div class="my-auto p-4">
        <%= live_redirect to: Routes.project_dataclip_edit_path(@socket, :edit, @work_order.workflow.project_id, @work_order.reason.dataclip_id) do %>
          <span
            title={@work_order.reason.dataclip_id}
            class="font-normal text-xs whitespace-nowrap text-ellipsis
            bg-gray-200 p-1 rounded-md font-mono text-indigo-400 hover:underline
            underline-offset-2 hover:text-indigo-500"
          >
            <%= display_short_uuid(@work_order.reason.dataclip_id) %>
          </span>
        <% end %>
      </div>
      <div class="my-auto p-4">
        <%= @work_order_inserted_at %>
      </div>
      <div class="my-auto p-4">
        <%= @last_run_finished_at %>
      </div>
      <div class="my-auto p-4">
        <div class="flex content-center justify-between">
          <%= case @last_run.exit_code do %>
            <% nil -> %>
              <%= if @last_run.finished_at do %>
                <.failure_pill>Timeout</.failure_pill>
              <% else %>
                <.pending_pill>Pending</.pending_pill>
              <% end %>
            <% val when val == 0 -> %>
              <.success_pill>Success</.success_pill>
            <% val when val > 0 -> %>
              <.failure_pill>Failure</.failure_pill>
          <% end %>

          <button
            class="w-auto rounded-full bg-gray-50 p-3 hover:bg-gray-100"
            phx-click="toggle_details"
            phx-target={@myself}
          >
            <%= if @show_details do %>
              <Heroicons.chevron_up outline class="h-3 w-3" />
            <% else %>
              <Heroicons.chevron_down outline class="h-3 w-3" />
            <% end %>
          </button>
        </div>
      </div>
      <%= if @show_details do %>
        <%= for attempt <- @attempts do %>
          <.attempt_item
            can_rerun_job={@can_rerun_job}
            attempt={attempt}
            project={@project}
          />
        <% end %>
      <% end %>
    </div>
    """
  end
end
