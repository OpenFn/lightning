defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  alias Lightning.Invocation
  use LightningWeb, :component
  import LightningWeb.RouteHelpers
  alias Lightning.WorkOrders.SearchParams
  alias Phoenix.LiveView.JS

  attr :project, :map, required: true
  attr :attempt, :map, required: true
  attr :can_rerun_job, :boolean, required: true

  def attempt_item(%{attempt: attempt} = assigns) do
    runs = attempt.runs
    last_run = List.last(runs)

    assigns =
      assigns
      |> assign(last_run: last_run, run_list: runs)

    ~H"""
    <div
      role="rowgroup"
      phx-mounted={JS.transition("fade-in-scale", time: 500)}
      id={"attempt-#{@attempt.id}"}
      data-entity="attempt"
      class="bg-gray-100"
    >
      <%= for run <- @run_list do %>
        <.run_list_item
          can_rerun_job={@can_rerun_job}
          project_id={@project.id}
          attempt={@attempt}
          run={run}
        />
      <% end %>
    </div>
    """
  end

  attr :run, :map, required: true
  attr :attempt, :map, required: true
  attr :project_id, :string, required: true
  attr :can_rerun_job, :boolean, required: true

  def run_list_item(assigns) do
    ~H"""
    <div role="row" class="grid grid-cols-8 items-center">
      <div
        role="cell"
        class="col-span-3 py-2 text-sm font-normal text-left rtl:text-right text-gray-500"
      >
        <div class="flex pl-28">
          <%= case @run.exit_reason do %>
            <% "fail" -> %>
              <%= if @run.finished_at do %>
                <Heroicons.x_circle
                  solid
                  class="mr-1.5 h-5 w-5 flex-shrink-0 text-red-500"
                />
              <% else %>
                <Heroicons.ellipsis_horizontal_circle
                  solid
                  class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-500"
                />
              <% end %>
            <% "success" -> %>
              <Heroicons.check_circle
                solid
                class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500"
              />
            <% nil -> %>
              <Heroicons.clock
                solid
                class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-500"
              />
            <% val -> %>
              <%= val %>
          <% end %>
          <div class="text-gray-800 flex gap-2 text-sm">
            <.link
              navigate={show_run_url(@project_id, @run.id)}
              target="_blank"
              class="hover:underline hover:underline-offset-2"
            >
              <span><%= @run.job.name %></span>
            </.link>
            <div class="flex gap-1">
              <%= if @can_rerun_job && @run.exit_reason do %>
                <span
                  id={@run.id}
                  class="text-indigo-400 hover:underline hover:underline-offset-2 hover:text-indigo-500 cursor-pointer"
                  phx-click="rerun"
                  phx-value-attempt_id={@attempt.id}
                  phx-value-run_id={@run.id}
                  title="Rerun workflow from here"
                >
                  rerun
                </span>
              <% end %>
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
        <.timestamp timestamp={@run.started_at} style={:wrapped} />
      </div>
      <div
        class="py-2 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
        role="cell"
      >
        <.timestamp timestamp={@run.finished_at} style={:wrapped} />
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

  def run_log_viewer(assigns) do
    assigns =
      assign(
        assigns,
        :log,
        Invocation.logs_for_run(assigns.run)
        |> Enum.map(fn log -> log.message end)
      )

    ~H"""
    <%= if length(@log) > 0 do %>
      <.log_view log={@log} />
    <% else %>
      <.no_log_message />
    <% end %>
    """
  end

  # --------------- Run Details ---------------
  attr :run, :any, required: true
  attr :show_input_dataclip, :boolean
  attr :class, :string, default: nil

  @spec run_viewer(map) :: Phoenix.LiveView.Rendered.t()
  def run_viewer(assigns) do
    assigns = assigns |> assign_new(:show_input_dataclip, fn -> false end)

    ~H"""
    <div class="flex flex-col h-full ">
      <div class="flex-0">
        <.run_details run={@run} />
        <.toggle_bar class="mt-4 items-end" phx-mounted={show_section("log")}>
          <%= if @show_input_dataclip do %>
            <.toggle_item data-section="input" phx-click={switch_section("input")}>
              Input
            </.toggle_item>
          <% end %>
          <.toggle_item data-section="output" phx-click={switch_section("output")}>
            Output
          </.toggle_item>
          <.toggle_item
            data-section="log"
            phx-click={switch_section("log")}
            active="true"
          >
            Log
          </.toggle_item>
        </.toggle_bar>
      </div>

      <div class="mt-4 flex-1 overflow-y-auto">
        <%= if @show_input_dataclip do %>
          <div
            id="input_section"
            style="display: none;"
            class="@container overflow-y-auto h-full"
          >
            <.dataclip_view dataclip={@run.input_dataclip} />
          </div>
        <% end %>

        <div
          id="log_section"
          style="display: none;"
          class="@container overflow-y-auto h-full rounded-md"
        >
          <.run_log_viewer run={@run} />
        </div>
        <div
          id="output_section"
          style="display: none;"
          class="@container h-full overflow-y-auto"
        >
          <%= cond  do %>
            <% is_nil(@run.exit_reason) -> %>
              <.dataclip_view
                dataclip={nil}
                no_dataclip_message={
                  %{
                    label: "This run has not yet finished.",
                    description:
                      "There is no output. See the logs for more information"
                  }
                }
              />
            <% @run.exit_reason != "success" -> %>
              <.dataclip_view
                dataclip={nil}
                no_dataclip_message={
                  %{
                    label: "This run failed",
                    description:
                      "There is no output. See the logs for more information"
                  }
                }
              />
            <% is_nil(@run.output_dataclip_id) -> %>
              <.dataclip_view
                dataclip={nil}
                no_dataclip_message={
                  %{
                    label: "There is no output for this run",
                    description:
                      "Check your job expression to ensure that the final operation returns something."
                  }
                }
              />
            <% true -> %>
              <.dataclip_view dataclip={@run.output_dataclip} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :run, :any, required: true

  def run_details(%{run: run} = assigns) do
    run_finished_at =
      cond do
        run.finished_at ->
          run.finished_at |> Calendar.strftime("%c.%f %Z")

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
          "..."

        true ->
          "Not started."
      end

    run_credential =
      if Ecto.assoc_loaded?(run.credential) && run.credential,
        do: "#{run.credential.name} (owned by #{run.credential.user.email})",
        else: nil

    run_job = get_in(run, [Access.key!(:job), Access.key(:name, run.job_id)])

    assigns =
      assigns
      |> assign(
        run_finished_at: run_finished_at,
        run_credential: run_credential,
        run_job: run_job,
        ran_for: ran_for
      )

    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex gap-4 flex-row text-xs lg:text-sm" id={"job-#{@run.id}"}>
        <div class="basis-1/2 font-semibold text-secondary-700">Job</div>
        <div class="basis-1/2 text-right"><%= @run_job %></div>
      </div>
      <div
        class="flex gap-4 flex-row text-xs lg:text-sm"
        id={"job-credential-#{@run.id}"}
      >
        <div class="basis-1/2 font-semibold text-secondary-700">Credential</div>
        <div class="basis-1/2 text-right"><%= @run_credential || "n/a" %></div>
      </div>
      <div
        class="flex gap-4 flex-row text-xs lg:text-sm"
        id={"finished-at-#{@run.id}"}
      >
        <div class="basis-1/2 font-semibold text-secondary-700">Finished</div>
        <div class="basis-1/2 text-right"><%= @run_finished_at %></div>
      </div>
      <div class="flex flex-row text-xs lg:text-sm" id={"ran-for-#{@run.id}"}>
        <div class="lg:basis-1/2 font-semibold text-secondary-700">Duration</div>
        <div class="basis-1/2 text-right"><%= @ran_for %></div>
      </div>
      <div class="flex flex-row text-xs lg:text-sm" id={"exit-reason-#{@run.id}"}>
        <div class="basis-1/2 font-semibold text-secondary-700">Exit Reason</div>
        <div class="basis-1/2 text-right">
          <%= case @run.exit_reason do %>
            <% "fail" -> %>
              <.failure_pill class="font-mono font-bold">fail</.failure_pill>
            <% "success" -> %>
              <.success_pill class="font-mono font-bold">success</.success_pill>
            <% nil -> %>
              <.pending_pill class="font-mono font-bold">running</.pending_pill>
            <% val -> %>
              <.other_state_pill class="font-mono font-bold">
                <%= val %>
              </.other_state_pill>
          <% end %>
        </div>
      </div>
    </div>
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

  attr :dataclip, :any, required: true
  attr :no_dataclip_message, :any

  def dataclip_view(%{dataclip: dataclip} = assigns) do
    lines =
      if dataclip do
        dataclip.body
        |> Jason.encode!()
        |> Jason.Formatter.pretty_print()
        |> String.split("\n")
      end

    assigns =
      assigns
      |> assign(lines: lines)
      |> assign_new(:no_dataclip_message, fn ->
        %{
          label: "Nothing here yet.",
          description: "The resulting dataclip will appear here
    when the run finishes successfully."
        }
      end)

    ~H"""
    <%= if @dataclip do %>
      <.log_view log={@lines} />
    <% else %>
      <.no_dataclip_message
        label={@no_dataclip_message.label}
        description={@no_dataclip_message.description}
      />
    <% end %>
    """
  end

  @spec no_dataclip_message(any) :: Phoenix.LiveView.Rendered.t()
  def no_dataclip_message(assigns) do
    ~H"""
    <div class="flex items-center flex-col mt-5 @md:w-1/4 @xs:w-1/2 m-auto">
      <div class="flex flex-col">
        <div class="m-auto">
          <Heroicons.question_mark_circle class="h-16 w-16 stroke-gray-400" />
        </div>
        <div class="font-sm text-slate-400 text-center">
          <span class="text-slate-500 font-semibold">
            <%= @label %>
          </span>
          <br /> <%= @description %>
        </div>
      </div>
    </div>
    """
  end

  def no_log_message(assigns) do
    ~H"""
    <div class="flex items-center flex-col mt-5 @md:w-1/4 @xs:w-1/2 m-auto">
      <div class="flex flex-col">
        <div class="m-auto">
          <Heroicons.question_mark_circle class="h-16 w-16 stroke-gray-400" />
        </div>
        <div class="font-sm text-slate-400 text-center">
          <span class="text-slate-500 font-semibold">
            Nothing here yet.
          </span>
          <br /> The resulting log will appear here when the run completes.
        </div>
      </div>
    </div>
    """
  end

  # ------------------- Toggle Bar ---------------------
  # Used to switch between Log and Output

  slot :inner_block, required: true
  attr :class, :string, default: "items-end"
  attr :rest, :global

  def toggle_bar(assigns) do
    ~H"""
    <div class={"flex flex-col #{@class}"} {@rest}>
      <div class="flex rounded-lg p-1 bg-gray-200 font-semibold">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr :active, :string, default: "false"
  slot :inner_block, required: true
  attr :rest, :global

  def toggle_item(assigns) do
    ~H"""
    <div
      data-active={@active}
      class="group text-sm shadow-sm text-gray-700
                     data-[active=true]:bg-white data-[active=true]:text-indigo-500
                     px-4 py-2 rounded-md align-middle flex items-center cursor-pointer"
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def switch_section(section) do
    JS.hide(to: "[id$=_section]:not([id=#{section}_section])")
    |> JS.set_attribute({"data-active", "false"},
      to: "[data-section]:not([data-section=#{section}])"
    )
    |> show_section(section)
  end

  def show_section(js \\ %JS{}, section) do
    js
    |> JS.show(
      to: "##{section}_section",
      transition: {"ease-out duration-300", "opacity-0", "opacity-100"},
      time: 200
    )
    |> JS.set_attribute({"data-active", "true"}, to: "[data-section=#{section}]")
  end

  # -------------------- Status Pills -------------------

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

  def killed_pill(assigns) do
    assigns = assigns |> apply_classes(~w[text-yellow-800 bg-yellow-200])

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

  def other_state_pill(assigns) do
    assigns = assigns |> apply_classes(~w[bg-black text-white])

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
                Run Selected Workers
              </h3>
              <div class="mt-2">
                <p class="text-sm text-gray-500">
                  <%= if @all_selected? do %>
                    You've selected all <%= @selected_count %> workorders from page <%= @page_number %> of <%= @pages %>. There are a total of <%= @total_entries %> that match your current query: <%= humanize_search_params(
                      @filters,
                      @workflows
                    ) %>.
                  <% else %>
                    You've selected <%= @selected_count %> workorders to rerun from the start. This will create a new attempt for each selected workorder.
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
                Rerun <%= @selected_count %> selected workorder<%= if @selected_count >
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
                Rerun all <%= @total_entries %> matching workorders from start
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
                Rerun <%= @selected_count %> selected workorder<%= if @selected_count >
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
