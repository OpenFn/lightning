defmodule LightningWeb.AttemptLive.Components do
  use LightningWeb, :component

  attr :attempt, Lightning.Attempt, required: true

  def elapsed_indicator(assigns) do
    ~H"""
    <div
      phx-hook="ElapsedIndicator"
      data-start-time={as_timestamp(@attempt.started_at)}
      data-finish-time={as_timestamp(@attempt.finished_at)}
      id={"elapsed-indicator-#{@attempt.id}"}
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
  # it's not really that complex!
  # credo:disable-for-next-line
  def state_pill(%{state: state} = assigns) do
    [text, classes] =
      case state do
        # only workorder states...
        :pending -> ["Enqueued", "bg-gray-200 text-gray-800"]
        :running -> ["Running", "bg-blue-200 text-blue-800"]
        # attempt & workorder states...
        :available -> ["Enqueued", "bg-gray-200 text-gray-800"]
        :claimed -> ["Starting", "bg-blue-200 text-blue-800"]
        :started -> ["Running", "bg-blue-200 text-blue-800"]
        :success -> ["Success", "bg-green-200 text-green-800"]
        :failed -> ["Failed", "bg-red-200 text-red-800"]
        :crashed -> ["Crashed", "bg-orange-200 text-orange-800"]
        :cancelled -> ["Cancelled", "bg-gray-500 text-gray-800"]
        :killed -> ["Killed", "bg-yellow-200 text-yellow-800"]
        :exception -> ["Exception", "bg-gray-800 text-white"]
        :lost -> ["Lost", "bg-gray-800 text-white"]
      end

    assigns = assign(assigns, text: text, classes: classes)

    ~H"""
    <span class={["my-auto whitespace-nowrap rounded-full
    py-2 px-4 text-center align-baseline text-xs font-medium leading-none", @classes]}>
      <%= @text %>
    </span>
    """
  end

  attr :run, Lightning.Invocation.Run, required: true
  attr :class, :string, default: ""

  def run_state_circle(%{run: run} = assigns) do
    assigns =
      assigns
      |> update(:class, fn class ->
        [
          class,
          case run.exit_reason do
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
      <.run_state_icon run={@run} class="h-6 w-6" />
    </span>
    """
  end

  attr :run, Lightning.Invocation.Run, required: true
  attr :class, :string, default: "h-4 w-4"

  # credo:disable-for-next-line
  def run_state_icon(%{run: run} = assigns) do
    assigns = assign(assigns, title: run.exit_reason)

    case {run.exit_reason, run.error_type} do
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
  Renders a list of runs for the attempt
  """
  attr :runs, :list, required: true
  attr :rest, :global
  slot :inner_block, required: true

  def step_list(assigns) do
    ~H"""
    <ul {@rest} role="list" class="-mb-8">
      <li :for={run <- @runs} data-run-id={run.id} class="group">
        <div class="relative pb-8">
          <span
            class="absolute left-4 top-4 -ml-px h-full w-0.5 bg-gray-200 group-last:hidden"
            aria-hidden="true"
          >
          </span>
          <%= render_slot(@inner_block, run) %>
        </div>
      </li>
    </ul>
    """
  end

  attr :run, Lightning.Invocation.Run, required: true
  attr :is_clone, :boolean, default: false
  attr :show_inspector_link, :boolean, default: false
  attr :attempt_id, :string
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
        <.run_state_circle run={@run} />
      </div>
      <div class={[
        "flex min-w-0 flex-1 space-x-1 pt-1.5 pr-1.5",
        if(@is_clone, do: "opacity-50")
      ]}>
        <%= if @is_clone do %>
          <div class="flex">
            <span
              class="cursor-pointer"
              id={"clone_" <> @run.id}
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
          <%= @run.job.name %>
          <%= if @show_inspector_link && !@run.job.scheduled_deletion do %>
            <.link navigate={
                ~p"/projects/#{@project_id}/w/#{@run.job.workflow_id}"
                  <> "?a=#{@attempt_id}&m=expand&s=#{@run.job_id}"
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
          <.run_duration run={@run} />
        </div>
      </div>
    </div>
    """
  end

  defp run_duration(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@run.started_at) -> %>
        Unknown
      <% is_nil(@run.finished_at) -> %>
        Running...
      <% true -> %>
        <%= DateTime.to_unix(@run.finished_at, :millisecond) -
          DateTime.to_unix(@run.started_at, :millisecond) %> ms
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
end
