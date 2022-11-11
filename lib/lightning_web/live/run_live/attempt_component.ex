defmodule LightningWeb.RunLive.AttemptComponent do
  @moduledoc """
  Attempt component for WorkOrder list module
  """
  use LightningWeb, :live_component

  @impl true
  def update(assigns, socket) do
    runs = assigns.attempt.runs
    last_run = List.last(runs)

    socket =
      socket
      |> assign(assigns)
      |> assign(:last_run, last_run)
      |> assign(:run_list, runs)

    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"attempt-#{@attempt.id}"}
      data-entity="attempt"
      class="col-span-5 mx-3 mb-3 rounded-lg bg-gray-100 p-6"
    >
      <ul class="list-inside list-none space-y-4 text-gray-500 dark:text-gray-400">
        <li>
          <span class="flex items-center">
            <Heroicons.clock solid class="mr-1 h-5 w-5" />
            <span>
              Run finished at <%= @last_run.finished_at
              |> Calendar.strftime("%c") %>

              <%= case @last_run.exit_code do %>
                <% nil -> %>
                  <span class="my-auto ml-2 whitespace-nowrap rounded-full bg-grey-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-grey-800">
                    Pending
                  </span>
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
            <%= for run <- @run_list do %>
              <.live_component
                module={LightningWeb.RunLive.RunComponent}
                id={run.id}
                run={run}
              />
            <% end %>
          </ol>
        </li>
      </ul>
    </div>
    """
  end
end
