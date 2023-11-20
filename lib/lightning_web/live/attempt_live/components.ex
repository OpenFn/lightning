defmodule LightningWeb.AttemptLive.Components do
  use LightningWeb, :component

  attr :attempt, :map, required: true
  attr :class, :string, default: ""

  def attempt_detail(assigns) do
    ~H"""
    <.detail_list id={"attempt-detail-#{@attempt.id}"} class={@class}>
      <.list_item>
        <:label>Attempt ID</:label>
        <:value><%= display_short_uuid(@attempt.id) %></:value>
      </.list_item>
      <.list_item>
        <:label>Elapsed time</:label>
        <:value>
          <div
            phx-hook="ElapsedIndicator"
            data-start-time={as_timestamp(@attempt.started_at)}
            data-finish-time={as_timestamp(@attempt.finished_at)}
            id={"elapsed-indicator-#{@attempt.id}"}
          />
        </:value>
      </.list_item>
      <.list_item>
        <:label>State</:label>
        <:value><.state_pill state={@attempt.state} /></:value>
      </.list_item>
    </.detail_list>
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
    <ul {@rest} role="list" class={["divide-y divide-gray-200", @class]}>
      <%= render_slot(@inner_block) %>
    </ul>
    """
  end

  slot :label
  slot :value

  def list_item(assigns) do
    ~H"""
    <li class="px-4 py-4 sm:px-0">
      <div class="flex justify-between">
        <dt class="font-medium">
          <%= render_slot(@label) %>
        </dt>
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
        :pending -> ["Pending", "bg-gray-200 text-gray-800"]
        :running -> ["Running", "bg-blue-200 text-blue-800"]
        # attempt & workorder states...
        :available -> ["Pending", "bg-gray-200 text-gray-800"]
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
end
