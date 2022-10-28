defmodule LightningWeb.RunLive.Components.WorkOrder do
  @moduledoc """
  Workorder component
  """
  use LightningWeb, :live_component
  import LightningWeb.RunLive.Components

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def handle_event("todo", %{}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <tr class="my-4 grid grid-cols-5 gap-4 rounded-lg bg-white">
      <th
        scope="row"
        class="my-auto whitespace-nowrap p-6 font-medium text-gray-900 dark:text-white"
      >
        <%= @work_order.workflow.name %>
      </th>
      <td class="my-auto p-6"><%= @work_order.reason.dataclip_id %></td>
      <td class="my-auto p-6">12i78iy</td>
      <td class="my-auto p-6">
        <%= @work_order.last_attempt.last_run.finished_at |> Calendar.strftime("%c") %>
      </td>
      <td class="my-auto p-6">
        <div class="flex content-center justify-between">
          <%= case @work_order.last_attempt.last_run.exit_code do %>
            <% val when val > 0-> %>
              <.failure_pill />
            <% val when val == 0 -> %>
              <.success_pill />
            <% _ -> %>
          <% end %>

          <button class="w-auto rounded-full bg-gray-50 p-3">
            <Heroicons.Outline.chevron_down class="h-5 w-5" />
          </button>
        </div>
      </td>
      <%= for attempt <- @work_order.attempts do %>
        <.live_component
          module={LightningWeb.RunLive.Components.Attempt}
          id={attempt.id}
          attempt={attempt}
        />
      <% end %>
    </tr>
    """
  end
end
