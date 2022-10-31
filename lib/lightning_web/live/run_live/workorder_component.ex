defmodule LightningWeb.RunLive.Components.WorkOrder do
  @moduledoc """
  Workorder component
  """
  use Phoenix.Component
  use LightningWeb, :live_component
  import LightningWeb.RunLive.Components

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def handle_event("toggle-details", %{}, socket) do
    {:noreply, assign(socket, :show_details, !socket.assigns[:show_details])}
  end

  @impl true
  def render(assigns) do
    assigns = assigns |> assign_new(:show_details, fn -> false end)

    ~H"""
    <tr class="my-4 grid grid-cols-5 gap-4 rounded-lg bg-white">
      <th
        scope="row"
        class="my-auto whitespace-nowrap p-6 font-medium text-gray-900 dark:text-white"
      >
        <%= @work_order.workflow.name %>
      </th>
      <td class="my-auto p-6"><%= @work_order.reason.dataclip_id %></td>
      <td class="my-auto p-6">
        <%= live_redirect to: Routes.project_dataclip_edit_path(@socket, :edit, @work_order.workflow.project_id, @work_order.reason.dataclip_id) do %>
          <div><%= @work_order.reason.id %></div>
        <% end %>
      </td>
      <td class="my-auto p-6">
        <%= @work_order.last_attempt.last_run.finished_at |> Calendar.strftime("%c") %>
      </td>
      <td class="my-auto p-6">
        <div class="flex content-center justify-between">
          <%= case @work_order.last_attempt.last_run.exit_code do %>
            <% val when val == 0 -> %>
              <.success_pill />
            <% val when val == 1-> %>
              <.failure_pill>Failure</.failure_pill>
            <% val when val == 2-> %>
              <.failure_pill>Timeout</.failure_pill>
            <% val when val > 2-> %>
              <.failure_pill>Crashed</.failure_pill>
            <% _ -> %>
          <% end %>

          <button
            class="w-auto rounded-full bg-gray-50 p-3 hover:bg-gray-100"
            phx-click="toggle-details"
            phx-target={@myself}
          >
            <%= if @show_details do %>
              <Heroicons.Outline.chevron_up class="h-5 w-5" />
            <% else %>
              <Heroicons.Outline.chevron_down class="h-5 w-5" />
            <% end %>
          </button>
        </div>
      </td>
      <%= if @show_details do %>
        <%= for attempt <- @work_order.attempts do %>
          <.live_component
            module={LightningWeb.RunLive.Components.Attempt}
            id={attempt.id}
            attempt={attempt}
          />
        <% end %>
      <% end %>
    </tr>
    """
  end
end
