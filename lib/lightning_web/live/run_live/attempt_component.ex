defmodule LightningWeb.RunLive.Components.Attempt do
  @moduledoc """
  Attempt component for WorkOrder list module
  """
  use LightningWeb, :live_component

  @impl true
  def update(assigns, socket) do
    last_run = Enum.at(assigns.attempt.runs, 0)

    socket =
      socket
      |> assign(assigns)
      |> assign(:last_run, last_run)

    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <td class="col-span-5 mx-3 mb-3 rounded-lg bg-gray-100 p-6">
      <ul class="list-inside list-none space-y-4 text-gray-500 dark:text-gray-400">
        <li>
          <span class="flex items-center">
            <Heroicons.clock solid class="mr-1 h-5 w-5" />
            <span>
              Re-run at <%= @last_run.finished_at
              |> Calendar.strftime("%c") %>

              <%= case @last_run.exit_code do %>
                <% val when val > 0-> %>
                  <span class="my-auto ml-2 whitespace-nowrap rounded-full bg-red-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-red-800">
                    Failure
                  </span>
                <% val when val == 0 -> %>
                  <span class="my-auto ml-2 whitespace-nowrap rounded-full bg-green-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-green-800">
                    Success
                  </span>
                <% _ -> %>
              <% end %>
            </span>
          </span>
          <ol class="mt-2 list-none space-y-4">
            <%= for run <- @attempt.runs do %>
              <.live_component
                module={LightningWeb.RunLive.Components.Run}
                id={run.id}
                run={run}
              />
            <% end %>
          </ol>
        </li>
      </ul>
    </td>
    """
  end
end
