defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.WorkOrders.SearchParams
  alias Phoenix.LiveView.JS

  attr :message, :string, required: true
  attr :class, :string, default: ""

  def async_filler(assigns) do
    ~H"""
    <div data-entity="work_order" class={["bg-gray-50", @class]}>
      <div class="py-3 text-center text-gray-500"><%= @message %></div>
    </div>
    """
  end

  attr :project, :map, required: true
  attr :attempt, :map, required: true
  attr :can_rerun_job, :boolean, required: true

  def attempt_item(%{attempt: attempt} = assigns) do
    steps = attempt.steps
    last_step = List.last(steps)

    assigns =
      assigns
      |> assign(last_step: last_step, step_list: steps)

    ~H"""
    <div
      role="rowgroup"
      phx-mounted={JS.transition("fade-in-scale", time: 500)}
      id={"attempt-#{@attempt.id}"}
      data-entity="attempt"
      class="bg-gray-100"
    >
      <%= for step <- @step_list do %>
        <.step_list_item
          can_rerun_job={@can_rerun_job}
          project_id={@project.id}
          attempt={@attempt}
          step={step}
        />
      <% end %>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :attempt, :map, required: true
  attr :project_id, :string, required: true
  attr :can_rerun_job, :boolean, required: true

  def step_list_item(assigns) do
    is_clone =
      DateTime.compare(assigns.step.inserted_at, assigns.attempt.inserted_at) ==
        :lt

    base_classes = ~w(grid grid-cols-8 items-center)

    step_item_classes =
      if is_clone, do: base_classes ++ ~w(opacity-50), else: base_classes

    assigns =
      assign(assigns, is_clone: is_clone, step_item_classes: step_item_classes)

    ~H"""
    <div id={"step-#{@step.id}"} role="row" class={@step_item_classes}>
      <div
        role="cell"
        class="col-span-3 py-2 text-sm font-normal text-left rtl:text-right text-gray-500"
      >
        <div class="flex pl-28">
          <.step_icon reason={@step.exit_reason} error_type={@step.error_type} />
          <div class="text-gray-800 flex gap-2 text-sm">
            <.link
              navigate={
                ~p"/projects/#{@project_id}/runs/#{@attempt}?#{%{step: @step.id}}"
              }
              class="hover:underline hover:underline-offset-2"
            >
              <span><%= @step.job.name %></span>
            </.link>
            <%= if @is_clone do %>
              <div class="flex gap-1">
                <span
                  class="cursor-pointer"
                  id={"clone_" <> @attempt.id <> "_" <> @step.id}
                  aria-label="This step was originally executed in a previous run.
                    It was skipped in this run; the original output has been
                    used as the starting point for downstream jobs."
                  phx-hook="Tooltip"
                  data-placement="right"
                >
                  <Heroicons.paper_clip
                    mini
                    class="mr-1.5 mt-1 h-3 w-3 flex-shrink-0 text-gray-500"
                  />
                </span>
              </div>
            <% end %>
            <div class="flex gap-1 text-xs leading-5">
              <%= if @can_rerun_job && @step.exit_reason do %>
                <span
                  id={@step.id}
                  class="text-indigo-400 hover:underline hover:underline-offset-2 hover:text-indigo-500 cursor-pointer"
                  phx-click="rerun"
                  phx-value-attempt_id={@attempt.id}
                  phx-value-step_id={@step.id}
                  title="Rerun workflow from here"
                >
                  rerun
                </span>/
              <% end %>
              <.link
                class="text-indigo-400 hover:underline hover:underline-offset-2 hover:text-indigo-500 cursor-pointer"
                navigate={
                ~p"/projects/#{@project_id}/w/#{@step.job.workflow_id}"
                  <> "?a=#{@attempt.id}&m=expand&s=#{@step.job_id}"
              }
              >
                inspect
              </.link>
            </div>
          </div>
        </div>
      </div>
      <div
        role="cell"
        class="py-2 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
      >
        --
      </div>
      <div
        role="cell"
        class="py-2 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
      >
        --
      </div>
      <div
        class="py-2 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
        role="cell"
      >
        <.timestamp timestamp={@step.started_at} style={:wrapped} />
      </div>
      <div
        class="py-2 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
        role="cell"
      >
        <.timestamp timestamp={@step.finished_at} style={:wrapped} />
      </div>
      <div role="cell"></div>
    </div>
    """
  end

  attr :timestamp, :any, required: true
  attr :style, :atom, default: :default

  def timestamp(assigns) do
    ~H"""
    <%= if is_nil(@timestamp) do %>
      <%= case @style do %>
        <% :wrapped -> %>
          <span>--</span>
          <br />
          <span class="font-medium text-gray-700">--</span>
        <% :default -> %>
          <span>--</span>
        <% :time_only -> %>
          <span>--</span>
      <% end %>
    <% else %>
      <%= case @style do %>
        <% :default -> %>
          <%= Timex.format!(
            @timestamp,
            "%d/%b/%y, %H:%M:%S",
            :strftime
          ) %>
        <% :wrapped -> %>
          <%= Timex.format!(
            @timestamp,
            "%d/%b/%y",
            :strftime
          ) %><br />
          <span class="font-medium text-gray-700">
            <%= Timex.format!(@timestamp, "%H:%M:%S", :strftime) %>
          </span>
        <% :time_only -> %>
          <%= Timex.format!(@timestamp, "%H:%M:%S", :strftime) %>
      <% end %>
    <% end %>
    """
  end

  attr :log, :list, required: true
  attr :class, :string, default: nil

  def log_view(%{log: log} = assigns) do
    assigns = assigns |> assign(log: log |> Enum.with_index(1))

    ~H"""
    <style>
      div.line-num::before { content: attr(data-line-number); padding-left: 0.1em; max-width: min-content;}
    </style>
    <div class={[
      "rounded-md text-slate-200 bg-slate-700 border-slate-300 shadow-sm
                    font-mono proportional-nums w-full text-sm overflow-y-auto min-h-full",
      @class
    ]}>
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

  @spec step_icon(%{
          :error_type => any(),
          :reason => nil | <<_::32, _::_*8>>,
          optional(any()) => any()
        }) :: Phoenix.LiveView.Rendered.t()
  # it's not really that complex!
  # credo:disable-for-next-line
  def step_icon(%{reason: reason, error_type: error_type} = assigns) do
    [icon, classes] =
      case {reason, error_type} do
        {nil, _any} -> [:pending, "text-gray-400"]
        {"success", _any} -> [:success, "text-green-500"]
        {"fail", _any} -> [:fail, "text-red-500"]
        {"crash", _any} -> [:crash, "text-orange-800"]
        {"cancel", _any} -> [:cancel, "text-grey-600"]
        {"kill", "SecurityError"} -> [:shield, "text-yellow-800"]
        {"kill", "ImportError"} -> [:shield, "text-yellow-800"]
        {"kill", "TimeoutError"} -> [:clock, "text-yellow-800"]
        {"kill", "OOMError"} -> [:circle_ex, "text-yellow-800"]
        {"exception", ""} -> [:triangle_ex, "text-black-800"]
        {"lost", _nil} -> [:triangle_ex, "text-black-800"]
      end

    assigns =
      assign(assigns,
        icon: icon,
        classes: ["mr-1.5 h-5 w-5 flex-shrink-0 inline", classes]
      )

    ~H"""
    <%= case @icon do %>
      <% :pending -> %>
        <Heroicons.clock solid class={@classes} />
      <% :success -> %>
        <Heroicons.check_circle solid class={@classes} />
      <% :fail -> %>
        <Heroicons.x_circle solid class={@classes} />
      <% :crash -> %>
        <Heroicons.x_circle solid class={@classes} />
      <% :cancel -> %>
        <Heroicons.no_symbol solid class={@classes} />
      <% :shield -> %>
        <Heroicons.shield_exclamation solid class={@classes} />
      <% :clock -> %>
        <Heroicons.clock solid class={@classes} />
      <% :circle_ex -> %>
        <Heroicons.exclamation_circle solid class={@classes} />
      <% :triangle_ex -> %>
        <Heroicons.exclamation_triangle solid class={@classes} />
    <% end %>
    """
  end

  # BULK RERUN
  attr :id, :string, required: true
  attr :page_number, :integer, required: true
  attr :pages, :integer, required: true
  attr :total_entries, :integer, required: true
  attr :all_selected?, :boolean, required: true
  attr :selected_count, :integer, required: true
  attr :filters, SearchParams, required: true
  attr :workflows, :list, required: true
  attr :show, :boolean, default: false

  def bulk_rerun_modal(assigns) do
    ~H"""
    <div
      class="relative z-10 hidden"
      aria-labelledby={"#{@id}-title"}
      id={@id}
      role="dialog"
      aria-modal="true"
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
      >
      </div>

      <div
        aria-labelledby={"#{@id}-title"}
        class="fixed inset-0 z-10 overflow-y-auto"
      >
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <.focus_wrap
            id={"#{@id}-container"}
            phx-mounted={@show && show_modal(@id)}
            phx-window-keydown={hide_modal(@id)}
            phx-key="escape"
            phx-click-away={hide_modal(@id)}
            class="hidden relative transform overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6"
          >
            <div id={"#{@id}-content"} class="mt-3 text-center sm:mt-5">
              <h3
                class="text-base font-semibold leading-6 text-gray-900"
                id={"#{@id}-title"}
              >
                Run Selected Work Orders
              </h3>
              <div class="mt-2">
                <p class="text-sm text-gray-500">
                  <%= if @all_selected? do %>
                    You've selected all <%= @selected_count %> work orders from page <%= @page_number %> of <%= @pages %>. There are a total of <%= @total_entries %> that match your current query: <%= humanize_search_params(
                      @filters,
                      @workflows
                    ) %>.
                  <% else %>
                    You've selected <%= @selected_count %> work orders to rerun from the start. This will create a new attempt for each selected work order.
                  <% end %>
                </p>
              </div>
            </div>
            <div
              :if={@all_selected? and @total_entries > 1 and @pages > 1}
              class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3"
            >
              <button
                type="button"
                phx-click="bulk-rerun"
                phx-value-type="selected"
                phx-disable-with="Running..."
                class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 sm:col-start-1"
              >
                Rerun <%= @selected_count %> selected work order<%= if @selected_count >
                                                                         1,
                                                                       do: "s",
                                                                       else: "" %> from start
              </button>
              <button
                type="button"
                phx-click="bulk-rerun"
                phx-value-type="all"
                phx-disable-with="Running..."
                class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 sm:col-start-2"
              >
                Rerun all <%= @total_entries %> matching work orders from start
              </button>
              <div class="relative col-start-1 col-end-3">
                <div class="absolute inset-0 flex items-center" aria-hidden="true">
                  <div class="w-full border-t border-gray-300"></div>
                </div>
                <div class="relative flex justify-center">
                  <span class="bg-white px-2 text-sm text-gray-500">
                    OR
                  </span>
                </div>
              </div>
              <button
                type="button"
                class="mt-3 inline-flex w-full justify-center items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:col-start-1 sm:col-end-3 sm:mt-0"
                phx-click={hide_modal(@id)}
              >
                Cancel
              </button>
            </div>
            <div
              :if={!@all_selected? or @total_entries == 1 or @pages == 1}
              class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3"
            >
              <button
                type="button"
                phx-click="bulk-rerun"
                phx-value-type="selected"
                phx-disable-with="Running..."
                class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 sm:col-start-2"
              >
                Rerun <%= @selected_count %> selected work order<%= if @selected_count >
                                                                         1,
                                                                       do: "s",
                                                                       else: "" %> from start
              </button>
              <button
                type="button"
                class="mt-3 inline-flex w-full justify-center items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:col-start-1 sm:mt-0"
                phx-click={hide_modal(@id)}
              >
                Cancel
              </button>
            </div>
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end

  defp humanize_search_params(filters, workflows) do
    filter =
      filters
      |> Map.from_struct()
      |> Enum.reject(fn {_key, val} -> is_nil(val) end)
      |> Enum.into(%{})

    params = [
      humanize_wo_dates(filter),
      humanize_workflow(filter, workflows),
      humanize_run_dates(filter),
      humanize_search_term(filter),
      humanize_status(filter)
    ]

    params |> Enum.reject(&(&1 == "")) |> Enum.join(", ")
  end

  defp humanize_wo_dates(filter) do
    case filter do
      %{wo_date_after: date_after, wo_date_before: date_before} ->
        "received between #{humanize_datetime(date_before)} and #{humanize_datetime(date_after)}"

      %{wo_date_after: date_after} ->
        "received after #{humanize_datetime(date_after)}"

      %{wo_date_before: date_before} ->
        "received before #{humanize_datetime(date_before)}"

      _other ->
        ""
    end
  end

  defp humanize_run_dates(filter) do
    case filter do
      %{date_after: date_after, date_before: date_before} ->
        "which was last run between #{humanize_datetime(date_before)} and #{humanize_datetime(date_after)}"

      %{date_after: date_after} ->
        "which was last run after #{humanize_datetime(date_after)}"

      %{date_before: date_before} ->
        "which was last run before #{humanize_datetime(date_before)}"

      _other ->
        ""
    end
  end

  defp humanize_search_term(filter) do
    case filter do
      %{search_term: search_term, search_fields: [_h | _t] = search_fields} ->
        "whose run #{Enum.map_join(search_fields, " and ", &humanize_field/1)} contain #{search_term}"

      _other ->
        ""
    end
  end

  defp humanize_workflow(filter, workflows) do
    case filter do
      %{workflow_id: workflow_id} ->
        {workflow, _id} =
          Enum.find(workflows, fn {_name, id} -> id == workflow_id end)

        "for #{workflow} workflow"

      _other ->
        ""
    end
  end

  defp humanize_status(filter) do
    case filter do
      %{status: [_1, _2 | _rest] = statuses} ->
        "having a status of either #{Enum.map_join(statuses, " or ", fn status -> "'#{humanize_field(status)}'" end)}"

      %{status: [status]} ->
        "having a status of '#{humanize_field(status)}'"

      _other ->
        ""
    end
  end

  defp humanize_field(search_field) do
    case to_string(search_field) do
      "log" -> "Logs"
      "body" -> "Input"
      other -> other |> to_string |> String.capitalize()
    end
  end

  defp humanize_datetime(date) do
    Timex.format!(date, "{D}/{M}/{YY} at {h12}:{m}{am}")
  end
end
