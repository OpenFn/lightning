defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  use LightningWeb, :component

  # Example Usage
  #  <Components.table>
  #    <Components.work_order status={:success}>
  #      <Components.attempt>
  #        <li>
  #          <span class="flex items-center">
  #            <Heroicons.Solid.clock class="mr-1 h-5 w-5" />
  #            <span>
  #              Re-run at 15 June 14:20:42
  #              <span class="my-auto ml-2 whitespace-nowrap rounded-full bg-green-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-green-800">
  #                Success
  #              </span>
  #            </span>
  #          </span>
  #          <ol class="mt-2 list-none space-y-4">
  #            <li>
  #              <span class="my-4 flex">
  #                &vdash;
  #                <span class="mx-2 flex">
  #                  <Heroicons.Solid.check_circle class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400" />
  #                  You might feel like you are being
  #                </span>
  #              </span>
  #              <ol class="space-y-4 pl-5">
  #                <li>
  #                  <span class="mx-1 flex">
  #                    &vdash;
  #                    <span class="ml-1">
  #                      are being really "organized" o
  #                    </span>
  #                  </span>
  #                </li>
  #              </ol>
  #            </li>
  #            <li>
  #              <span class="flex">
  #                &vdash;
  #                <span class="mx-2 flex">
  #                  <Heroicons.Solid.check_circle class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400" />
  #                  You might feel like you are being
  #                </span>
  #              </span>
  #            </li>
  #            <li>
  #              <span class="flex">
  #                &vdash;
  #                <span class="mx-2 flex">
  #                  <Heroicons.Solid.check_circle class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400" />
  #                  You might feel like you are being
  #                </span>
  #              </span>
  #            </li>
  #          </ol>
  #        </li>
  #      </Components.attempt>
  #      <Components.attempt>
  #        <li>
  #          <span class="flex items-center">
  #            <Heroicons.Solid.clock class="mr-1 h-5 w-5" />
  #            <span>
  #              Run at 15 June 14:20:42
  #              <span class="my-auto ml-2 whitespace-nowrap rounded-full bg-red-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-red-800">
  #                Failure
  #              </span>
  #            </span>
  #          </span>
  #        </li>
  #      </Components.attempt>
  #    </Components.work_order>
  #    <Components.work_order status={:failure} />
  #    <Components.work_order status={:success} />
  #  </Components.table>

  # coveralls-ignore-start
  def table(assigns) do
    ~H"""
    <div class="overflow-x-auto bg-gray-100 dark:bg-gray-700">
      <table class="w-full border-separate border-spacing-y-4 text-left text-sm text-gray-500 dark:text-gray-400">
        <thead class="text-xs uppercase text-gray-400 dark:text-gray-400">
          <tr class="grid grid-cols-4 gap-4">
            <th scope="col" class="py-3 px-6 font-medium">Workflow name</th>
            <th scope="col" class="py-3 px-6 font-medium">Input</th>
            <th scope="col" class="py-3 px-6 font-medium">Last run</th>
            <th scope="col" class="py-3 px-6 font-medium">Status</th>
          </tr>
        </thead>
        <tbody class="bg-gray-100">
          <%= render_slot(@inner_block) %>
        </tbody>
      </table>
    </div>
    """
  end

  def work_order(assigns) do
    assigns = assigns |> assign_new(:status, fn -> nil end)

    ~H"""
    <tr class="my-4 grid grid-cols-4 gap-4 rounded-lg bg-white">
      <th
        scope="row"
        class="my-auto whitespace-nowrap p-6 font-medium text-gray-900 dark:text-white"
      >
        workFlowName
      </th>
      <td class="my-auto p-6">12i78iy</td>
      <td class="my-auto p-6">UTC 24:20:60</td>
      <td class="my-auto p-6">
        <div class="flex content-center justify-between">
          <%= case @status do %>
            <% :failure -> %>
              <.failure_pill />
            <% :success -> %>
              <.success_pill />
            <% _ -> %>
          <% end %>

          <button class="w-auto rounded-full bg-gray-50 p-3">
            <Heroicons.Outline.chevron_down class="h-5 w-5" />
          </button>
        </div>
      </td>
      <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
    </tr>
    """
  end

  def attempt(assigns) do
    ~H"""
    <td class="col-span-4 mx-3 mb-3 rounded-lg bg-gray-100 p-6">
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

  # coveralls-ignore-stop
end
