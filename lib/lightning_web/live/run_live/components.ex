defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.WorkOrders.SearchParams
  alias Phoenix.LiveView.JS

  attr :run, Lightning.Run, required: true

  def elapsed_indicator(assigns) do
    ~H"""
    <div
      phx-hook="ElapsedIndicator"
      data-start-time={as_timestamp(@run.started_at)}
      data-finish-time={as_timestamp(@run.finished_at)}
      id={"elapsed-indicator-#{@run.id}"}
    />
    """
  end

  defp as_timestamp(datetime) do
    if datetime do
      datetime |> DateTime.to_unix(:millisecond)
    end
  end

  slot :inner_block
  attr :class, :string, default: ""
  attr :rest, :global

  def detail_list(assigns) do
    ~H"""
    <ul
      {@rest}
      role="list"
      class={["flex-1 @5xl/viewer:flex-none", "divide-y divide-gray-200", @class]}
    >
      <%= render_slot(@inner_block) %>
    </ul>
    """
  end

  slot :label do
    attr :class, :string
  end

  slot :value

  def list_item(assigns) do
    ~H"""
    <li class="px-4 py-4 sm:px-0">
      <div class="flex justify-between items-baseline text-sm @md/viewer:text-base">
        <%= for label <- @label do %>
          <dt class={["font-medium items-center", label[:class]]}>
            <%= render_slot(label) %>
          </dt>
        <% end %>
        <dd class="text-gray-900 font-mono">
          <%= render_slot(@value) %>
        </dd>
      </div>
    </li>
    """
  end

  attr :state, :atom, required: true

  @spec state_pill(%{:state => any(), optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  @spec state_pill(map()) :: Phoenix.LiveView.Rendered.t()
  def state_pill(%{state: state} = assigns) do
    chip_styles = %{
      # only workorder states...
      pending: "bg-gray-200 text-gray-800",
      running: "bg-blue-200 text-blue-800",
      #  run and workorder states...
      available: "bg-gray-200 text-gray-800",
      claimed: "bg-blue-200 text-blue-800",
      started: "bg-blue-200 text-blue-800",
      success: "bg-green-200 text-green-800",
      failed: "bg-red-200 text-red-800",
      crashed: "bg-orange-200 text-orange-800",
      cancelled: "bg-gray-500 text-gray-800",
      killed: "bg-yellow-200 text-yellow-800",
      exception: "bg-gray-800 text-white",
      lost: "bg-gray-800 text-white"
    }

    assigns =
      assign(assigns,
        text: display_text_from_state(state),
        classes: Map.get(chip_styles, state)
      )

    ~H"""
    <span class={["my-auto whitespace-nowrap rounded-full
    py-2 px-4 text-center align-baseline text-xs font-medium leading-none", @classes]}>
      <%= @text %>
    </span>
    """
  end

  def display_text_from_state(state) do
    case state do
      # only workorder states...
      :pending -> "Enqueued"
      :running -> "Running"
      # run & workorder states...
      :available -> "Enqueued"
      :claimed -> "Starting"
      :started -> "Running"
      atom -> to_string(atom) |> String.capitalize()
    end
  end

  attr :step, Lightning.Invocation.Step, required: true
  attr :class, :string, default: ""

  def step_state_circle(%{step: step} = assigns) do
    assigns =
      assigns
      |> update(:class, fn class ->
        [
          class,
          case step.exit_reason do
            "success" -> ["bg-green-200 text-green-800"]
            "fail" -> ["bg-red-200 text-red-800"]
            "crash" -> ["bg-orange-200 text-orange-800"]
            "cancel" -> ["bg-gray-500 text-gray-800"]
            "kill" -> ["bg-yellow-200 text-yellow-800"]
            "exception" -> ["bg-gray-800 text-white"]
            "lost" -> ["bg-gray-800 text-white"]
            _ -> ["bg-blue-200 text-blue-800"]
          end
        ]
      end)

    ~H"""
    <span class={[
      "h-8 w-8 rounded-full",
      "flex items-center justify-center",
      "ring-8 ring-secondary-100",
      @class
    ]}>
      <.step_state_icon step={@step} class="h-6 w-6" />
    </span>
    """
  end

  attr :step, Lightning.Invocation.Step, required: true
  attr :class, :string, default: "h-4 w-4"

  # credo:disable-for-next-line
  def step_state_icon(%{step: step} = assigns) do
    assigns = assign(assigns, title: step.exit_reason)

    case {step.exit_reason, step.error_type} do
      {"success", _} ->
        ~H[<.icon title={@title} name="hero-check-circle" class={@class} />]

      {"fail", _} ->
        ~H[<.icon title={@title} name="hero-x-circle" class={@class} />]

      {"crash", _} ->
        ~H[<.icon title={@title} name="hero-x-circle" class={@class} />]

      {"cancel", _} ->
        ~H[<.icon title={@title} name="hero-check-circle" class={@class} />]

      {"kill", error_type} when error_type in ["SecurityError", "ImportError"] ->
        ~H[<.icon title={@title} name="hero-shield-exclamation" class={@class} />]

      {"kill", error_type} when error_type == "TimeoutError" ->
        ~H[<.icon title={@title} name="hero-clock" class={@class} />]

      {"kill", _} ->
        ~H[<.icon title={@title} name="hero-exclamation-circle" class={@class} />]

      {"exception", _} ->
        ~H[<.icon title={@title} name="hero-exclamation-triangle" class={@class} />]

      {"lost", _} ->
        ~H[<.icon title={@title} name="hero-exclamation-triangle" class={@class} />]

      _ ->
        ~H[<.icon title="running" name="hero-ellipsis-horizontal" class={@class} />]
    end
  end

  @doc """
  Renders a list of steps for the run
  """
  attr :steps, :list, required: true
  attr :rest, :global
  slot :inner_block, required: true

  def step_list(assigns) do
    ~H"""
    <ul {@rest} role="list" class="-mb-8">
      <li :for={step <- @steps} data-step-id={step.id} class="group">
        <div class="relative pb-8">
          <span
            class="absolute left-4 top-4 -ml-px h-full w-0.5 bg-gray-200 group-last:hidden"
            aria-hidden="true"
          >
          </span>
          <%= render_slot(@inner_block, step) %>
        </div>
      </li>
    </ul>
    """
  end

  attr :step, Lightning.Invocation.Step, required: true
  attr :is_clone, :boolean, default: false
  attr :show_inspector_link, :boolean, default: false
  attr :run_id, :string
  attr :project_id, :string
  attr :selected, :boolean, default: false
  attr :class, :string, default: ""
  attr :rest, :global

  def step_item(assigns) do
    # TODO - add dataclip and workorder
    # <> "?i=DATACLIP_ID&m=expand&wo=WORKORDER_ID"

    ~H"""
    <div
      class={[
        "relative flex space-x-3 border-r-4",
        if(@selected,
          do: "border-primary-500",
          else: "border-transparent hover:border-gray-300"
        ),
        @class
      ]}
      {@rest}
    >
      <div class="flex items-center">
        <.step_state_circle step={@step} />
      </div>
      <div class={[
        "flex min-w-0 flex-1 space-x-1 pt-1.5 pr-1.5",
        if(@is_clone, do: "opacity-50")
      ]}>
        <%= if @is_clone do %>
          <div class="flex">
            <span
              class="cursor-pointer"
              id={"clone_" <> @step.id}
              aria-label="This step was originally executed in a previous run.
                    It was skipped in this run; the original output has been
                    used as the starting point for downstream jobs."
              phx-hook="Tooltip"
              data-placement="bottom"
            >
              <Heroicons.paper_clip
                mini
                class="mr-1 mt-1 h-3 w-3 flex-shrink-0 text-gray-500"
              />
            </span>
          </div>
        <% end %>
        <div class="flex text-sm space-x-1 text-gray-900">
          <%= @step.job.name %>
          <%= if @show_inspector_link do %>
            <.link navigate={
                ~p"/projects/#{@project_id}/w/#{@step.job.workflow_id}"
                  <> "?a=#{@run_id}&m=expand&s=#{@step.job_id}"
              }>
              <.icon
                title="Inspect Step"
                name="hero-document-magnifying-glass-mini"
                class="h-4 w-4 mb-2 hover:text-primary-400"
              />
            </.link>
          <% end %>
        </div>
        <div class="flex-grow whitespace-nowrap text-right text-sm text-gray-500">
          <.step_duration step={@step} />
        </div>
      </div>
    </div>
    """
  end

  defp step_duration(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@step.started_at) -> %>
        Unknown
      <% is_nil(@step.finished_at) -> %>
        Running...
      <% true -> %>
        <%= DateTime.to_unix(@step.finished_at, :millisecond) -
          DateTime.to_unix(@step.started_at, :millisecond) %> ms
    <% end %>
    """
  end

  def loading_filler(assigns) do
    ~H"""
    <.detail_list class="animate-pulse">
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-16">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-24"></span>
        </:value>
      </.list_item>
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12"></span>
        </:value>
      </.list_item>
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-24"></span>
        </:value>
      </.list_item>
    </.detail_list>
    """
  end

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
  attr :run, :map, required: true
  attr :can_edit_data_retention, :boolean, required: true
  attr :can_run_workflow, :boolean, required: true

  def run_item(%{run: run} = assigns) do
    steps = run.steps
    last_step = List.last(steps)

    assigns =
      assigns
      |> assign(last_step: last_step, step_list: steps)

    ~H"""
    <div
      role="rowgroup"
      phx-mounted={JS.transition("fade-in-scale", time: 500)}
      id={"run-#{@run.id}"}
      data-entity="run"
      class="bg-gray-100"
    >
      <%= for step <- @step_list do %>
        <.step_list_item
          can_run_workflow={@can_run_workflow}
          project_id={@project.id}
          run={@run}
          can_edit_data_retention={@can_edit_data_retention}
          step={step}
        />
      <% end %>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :run, :map, required: true
  attr :project_id, :string, required: true
  attr :can_run_workflow, :boolean, required: true
  attr :can_edit_data_retention, :boolean, required: true

  def step_list_item(assigns) do
    is_clone =
      DateTime.compare(assigns.step.inserted_at, assigns.run.inserted_at) ==
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
                ~p"/projects/#{@project_id}/runs/#{@run}?#{%{step: @step.id}}"
              }
              class="hover:underline hover:underline-offset-2"
            >
              <span><%= @step.job.name %></span>
            </.link>
            <%= if @is_clone do %>
              <div class="flex gap-1">
                <span
                  class="cursor-pointer"
                  id={"clone_" <> @run.id <> "_" <> @step.id}
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
              <%= if @can_run_workflow && @step.exit_reason do %>
                <.step_rerun_tag {assigns} />/
              <% end %>
              <.link
                class="text-indigo-400 hover:underline hover:underline-offset-2 hover:text-indigo-500 cursor-pointer"
                navigate={
                ~p"/projects/#{@project_id}/w/#{@step.job.workflow_id}"
                  <> "?a=#{@run.id}&m=expand&s=#{@step.job_id}"
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

  defp step_rerun_tag(assigns) do
    ~H"""
    <%= if @step.input_dataclip && is_nil(@step.input_dataclip.wiped_at) do %>
      <span
        id={@step.id}
        class="text-indigo-400 hover:underline hover:underline-offset-2 hover:text-indigo-500 cursor-pointer"
        phx-click="rerun"
        phx-value-run_id={@run.id}
        phx-value-step_id={@step.id}
        title="Rerun workflow from here"
      >
        rerun
      </span>
    <% else %>
      <span
        id={@step.id}
        class="text-indigo-300 cursor-pointer"
        phx-hook="Tooltip"
        data-placement="top"
        data-allow-html="true"
        aria-label={
          rerun_zero_persistence_tooltip_message(
            @project_id,
            @can_edit_data_retention
          )
        }
      >
        rerun
      </span>
    <% end %>
    """
  end

  def rerun_zero_persistence_tooltip_message(project_id, can_edit_retention) do
    """
    <span class="text-center">
    This work order cannot be rerun since no input data has been stored due to
    the data retention policy set in the project.
    <br />
    #{zero_persistence_action_message(project_id, can_edit_retention)}
    </span>
    """
  end

  def zero_persistence_action_message(project_id, can_edit_retention) do
    if can_edit_retention do
      """
      <a href="#{~p"/projects/#{project_id}/settings#data-storage"}" class="underline text-blue-400">
      Go to data storage settings
      </a>
      """
    else
      "For more information, contact one of your project admins"
    end
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
        <Heroicons.ellipsis_horizontal_circle solid class={@classes} />
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
                    You've selected <%= @selected_count %> work orders to rerun from the start. This will create a new run for each selected work order.
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
