defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  use LightningWeb, :component

  def table(assigns) do
    ~H"""
    <div class="bg-gray-100 dark:bg-gray-700 relative">
      <div
        data-entity="work_order_index"
        class="flex flex-col h-full w-full border-separate border-spacing-y-4 text-left text-sm text-gray-500 dark:text-gray-400"
      >
        <div class="sticky top-0 bg-gray-100 text-xs uppercase text-gray-400 dark:text-gray-400">
          <div class="grid grid-cols-5 gap-4">
            <div class="py-3 px-6 font-medium">Workflow name</div>
            <div class="py-3 px-6 font-medium">Reason</div>
            <div class="py-3 px-6 font-medium">Input</div>
            <div class="py-3 px-6 font-medium">Last run</div>
            <div class="py-3 px-6 font-medium">Status</div>
          </div>
        </div>
        <div data-entity="work_order_list" class="bg-gray-100">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  def work_order(assigns) do
    assigns = assigns |> assign_new(:status, fn -> nil end)

    ~H"""
    <tr class="my-4 grid grid-cols-5 gap-4 rounded-lg bg-white">
      <th
        scope="row"
        class="my-auto whitespace-nowrap p-6 font-medium text-gray-900 dark:text-white"
      >
        <%= @workflow.name %>
      </th>
      <td class="my-auto p-6"><%= @reason.dataclip_id %></td>
      <td class="my-auto p-6">12i78iy</td>
      <td class="my-auto p-6">
        <%= @last_attempt.last_run.finished_at |> Calendar.strftime("%c") %>
      </td>
      <td class="my-auto p-6">
        <div class="flex content-center justify-between">
          <%= case @last_attempt.last_run.exit_code do %>
            <% val when val > 0-> %>
              <.failure_pill />
            <% val when val == 0 -> %>
              <.success_pill />
            <% _ -> %>
          <% end %>

          <button class="w-auto rounded-full bg-gray-50 p-3">
            <Heroicons.chevron_down class="h-5 w-5" />
          </button>
        </div>
      </td>
      <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
    </tr>
    """
  end

  def attempt(assigns) do
    ~H"""
    <td class="col-span-5 mx-3 mb-3 rounded-lg bg-gray-100 p-6">
      <ul class="list-inside list-none space-y-4 text-gray-500 dark:text-gray-400">
        <%= render_slot(@inner_block) %>
      </ul>
    </td>
    """
  end

  def failure_pill(assigns) do
    ~H"""
    <span class="text-green-red my-auto whitespace-nowrap rounded-full bg-red-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-red-800">
      Failure
    </span>
    """
  end

  def success_pill(assigns) do
    ~H"""
    <span class="my-auto whitespace-nowrap rounded-full bg-green-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-green-800">
      Success
    </span>
    """
  end

  def pending_pill(assigns) do
    ~H"""
    <span class="my-auto whitespace-nowrap rounded-full bg-grey-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-grey-800">
      Pending
    </span>
    """
  end
end
