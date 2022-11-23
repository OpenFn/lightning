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
            <% nil -> %>
              <Heroicons.ellipsis_horizontal_circle
                solid
                class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-500"
              />
            <% val when val > 0-> %>
              <Heroicons.x_circle
                solid
                class="mr-1.5 h-5 w-5 flex-shrink-0 text-red-500"
              />
            <% val when val == 0 -> %>
              <Heroicons.check_circle
                solid
                class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500"
              />
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

  attr :run, :any, required: true

  def run_details(%{run: run} = assigns) do
    run_finished_at =
      cond do
        run.finished_at ->
          run.finished_at |> Calendar.strftime("%c")

        run.started_at ->
          "Running..."

        true ->
          "Not started."
      end

    ran_for =
      cond do
        run.finished_at ->
          "#{DateTime.diff(run.finished_at, run.started_at, :millisecond)} ms"

        run.started_at ->
          "#{DateTime.diff(DateTime.utc_now(), run.started_at, :millisecond)} ms"

        true ->
          "Not started."
      end

    assigns =
      assigns
      |> assign(
        run_finished_at: run_finished_at,
        ran_for: ran_for
      )

    ~H"""
    <div class="flex flex-row" id={"finished-at-#{@run.id}"}>
      <div class="basis-1/2 font-semibold text-secondary-700">Finished</div>
      <div class="basis-1/2 text-right"><%= @run_finished_at %></div>
    </div>
    <div class="flex flex-row" id={"ran-for-#{@run.id}"}>
      <div class="basis-1/2 font-semibold text-secondary-700">Ran for</div>
      <div class="basis-1/2 text-right"><%= @ran_for %></div>
    </div>
    <div class="flex flex-row" id={"exit-code-#{@run.id}"}>
      <div class="basis-1/2 font-semibold text-secondary-700">Exit Code</div>
      <div class="basis-1/2 text-right">
        <%= case @run.exit_code do %>
          <% nil -> %>
            <.pending_pill class="font-mono font-bold">?</.pending_pill>
          <% val when val > 0-> %>
            <.failure_pill class="font-mono font-bold"><%= val %></.failure_pill>
          <% val when val == 0 -> %>
            <.success_pill class="font-mono font-bold">0</.success_pill>
        <% end %>
      </div>
    </div>
    """
  end

  attr :log, :list, required: true

  def log_view(%{log: log} = assigns) do
    assigns = assigns |> assign(log: log |> Enum.with_index(1))

    ~H"""
    <style>
      div.line-num::before { content: attr(data-line-number); padding-left: 0.1em; max-width: min-content; }
    </style>
    <div class="rounded-md mt-4 text-slate-200 bg-slate-700 border-slate-300 shadow-sm
                    font-mono proportional-nums w-full">
      <%= for { line, i } <- @log do %>
        <.log_line num={i} line={line} />
      <% end %>
    </div>
    """
  end

  attr :line, :string, required: true
  attr :num, :integer, required: true

  def log_line(%{line: line, num: num} = assigns) do
    # Format the log lines replacing single spaces with non-breaking spaces.
    assigns =
      assigns
      |> assign(
        line: line |> spaces_to_nbsp(),
        num: num |> to_string() |> String.pad_leading(3) |> spaces_to_nbsp()
      )

    ~H"""
    <div class="group flex flex-row hover:bg-slate-600
              first:hover:rounded-tr-md first:hover:rounded-tl-md
              last:hover:rounded-br-md last:hover:rounded-bl-md ">
      <div
        data-line-number={@num}
        class="line-num grow-0 border-r border-slate-500 align-top
                pr-2 text-right text-slate-400 inline-block
                group-hover:text-slate-300 group-first:pt-2 group-last:pb-2"
      >
      </div>
      <div data-log-line class="grow pl-2 group-first:pt-2 group-last:pb-2">
        <pre class="whitespace-pre-line break-all"><%= @line %></pre>
      </div>
    </div>
    """
  end

  defp spaces_to_nbsp(str) when is_binary(str) do
    str
    |> String.codepoints()
    |> Enum.map(fn
      " " -> raw("&nbsp;")
      c -> c
    end)
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
    assigns = assigns |> apply_classes(~w[bg-gray-200 text-gray-800])

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
