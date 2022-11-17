defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  use LightningWeb, :component
  import LightningWeb.RouteHelpers

  def attempt_item(assigns) do
    runs = assigns.attempt.runs
    last_run = List.last(runs)

    assigns =
      assigns
      |> assign(last_run: last_run, run_list: runs)

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
              <%= if @last_run.finished_at do %>
                Run finished at <%= @last_run.finished_at |> Calendar.strftime("%c") %>
              <% else %>
                Running...
              <% end %>

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
              <.run_list_item project={@project} run={run} />
            <% end %>
          </ol>
        </li>
      </ul>
    </div>
    """
  end

  def run_list_item(assigns) do
    ~H"""
    <li>
      <span class="my-4 flex">
        &vdash;
        <span class="mx-2 flex">
          <%= case @run.exit_code do %>
            <% val when val > 0-> %>
              <Heroicons.x_circle
                solid
                class="mr-1.5 h-5 w-5 flex-shrink-0 text-red-500 dark:text-red-400"
              />
            <% val when val == 0 -> %>
              <Heroicons.check_circle
                solid
                class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400"
              />
            <% _ -> %>
          <% end %>

          <.link
            navigate={show_run_path(@project.id, @run.id)}
            class="hover:underline hover:underline-offset-2"
          >
            <%= @run.job.name %>
          </.link>
        </span>
      </span>
    </li>
    """
  end

  @base_classes ~w[
    my-auto whitespace-nowrap rounded-full
    py-2 px-4 text-center align-baseline text-xs font-medium leading-none
  ]

  def failure_pill(assigns) do
    assigns = assigns |> apply_classes(~w[text-red-800 bg-red-200])

    ~H"""
    <span class={@classes}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  def success_pill(assigns) do
    assigns =
      assigns
      |> apply_classes(~w[bg-green-200 text-green-800])

    ~H"""
    <span class={@classes}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  def pending_pill(assigns) do
    assigns = assigns |> apply_classes(~w[bg-grey-200 text-grey-800])

    ~H"""
    <span class={@classes}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp apply_classes(assigns, classes) do
    assign(assigns,
      classes: @base_classes ++ classes ++ List.wrap(assigns[:class])
    )
  end
end
