defmodule LightningWeb.RunLive.Components.WorkOrder do
  @moduledoc """
  Workorder component
  """
  use Phoenix.Component
  use LightningWeb, :live_component
  import LightningWeb.RunLive.Components

  @impl true
  def update(assigns, socket) do
    last_attempt = Enum.at(assigns.work_order.attempts, 0)
    last_run = Enum.at(last_attempt.runs, 0)

    socket =
      socket
      |> assign(assigns)
      |> assign(:last_attempt, last_attempt)
      |> assign(:last_run, last_run)
      |> assign(:workflow_name, assigns.work_order.workflow.name || "Untitled")

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle-details", %{}, socket) do
    {:noreply, assign(socket, :show_details, !socket.assigns[:show_details])}
  end

  @impl true
  def render(assigns) do
    assigns = assigns |> assign_new(:show_details, fn -> false end)

    ~H"""
    <div class="my-4 grid grid-cols-5 gap-4 rounded-lg bg-white">
      <div
        scope="row"
        class="my-auto whitespace-nowrap p-6 font-medium text-gray-900 dark:text-white"
      >
        <%= @workflow_name %>
      </div>
      <div class="my-auto p-6"><%= @work_order.reason.dataclip_id %></div>
      <div class="my-auto p-6">
        <%= live_redirect to: Routes.project_dataclip_edit_path(@socket, :edit, @work_order.workflow.project_id, @work_order.reason.dataclip_id) do %>
          <div><%= @work_order.reason.id %></div>
        <% end %>
      </div>
      <div class="my-auto p-6">
        <%= @last_run.finished_at |> Calendar.strftime("%c") %>
      </div>
      <div class="my-auto p-6">
        <div class="flex content-center justify-between">
          <%= case @last_run.exit_code do %>
            <% val when val == 0 -> %>
              <.success_pill />
            <% _ -> %>
              <.failure_pill>Failure</.failure_pill>
          <% end %>

          <button
            class="w-auto rounded-full bg-gray-50 p-3 hover:bg-gray-100"
            phx-click="toggle-details"
            phx-target={@myself}
          >
            <%= if @show_details do %>
              <Heroicons.chevron_up outline class="h-5 w-5" />
            <% else %>
              <Heroicons.chevron_down outline class="h-5 w-5" />
            <% end %>
          </button>
        </div>
      </div>
      <%= if @show_details do %>
        <%= for attempt <- @work_order.attempts do %>
          <.live_component
            module={LightningWeb.RunLive.Components.Attempt}
            id={attempt.id}
            attempt={attempt}
          />
        <% end %>
      <% end %>
    </div>
    """
  end
end
