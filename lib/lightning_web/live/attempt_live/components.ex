defmodule LightningWeb.AttemptLive.Components do
  use LightningWeb, :component

  @doc """
  Renders out a log line stream
  """

  attr :id, :string, required: true
  attr :stream, :list, required: true
  attr :class, :string, default: nil

  def log_view(assigns) do
    ~H"""
    <div
      class={[
        "rounded-md text-slate-200 bg-slate-700 border-slate-300 shadow-sm
         font-mono proportional-nums w-full text-sm overflow-y-auto
         overscroll-contain scroll-smooth",
        @class
      ]}
      id={"log-lines-#{@id}"}
      phx-update="stream"
    >
      <div
        id="empty-log-lines"
        class="hidden only:block m-2 relative block rounded-md
               border-2 border-dashed border-gray-500 p-12 text-center"
      >
        Nothing yet...
      </div>
      <div
        :for={{dom_id, log_line} <- @stream}
        class="group flex flex-row hover:bg-slate-600
              first:hover:rounded-tr-md first:hover:rounded-tl-md
              last:hover:rounded-br-md last:hover:rounded-bl-md "
        data-run-id={log_line.run_id}
        id={dom_id}
      >
        <div class="line-log-level grow-0 border-r border-slate-500 align-top
                px-2 text-right text-slate-400 inline-block
                group-hover:text-slate-300 group-first:pt-2 group-last:pb-2">
          <%= log_line.source %>
        </div>
        <div data-log-line class="grow pl-2 group-first:pt-2 group-last:pb-2">
          <pre class="whitespace-pre-line break-all"><%= log_line.message %></pre>
        </div>
      </div>
    </div>
    """
  end

  attr :attempt, :map, required: true
  attr :class, :string, default: ""

  def attempt_detail(assigns) do
    ~H"""
    <.detail_list class={@class}>
      <.list_item>
        <:label>Attempt ID</:label>
        <:value><%= String.slice(@attempt.id, 0..7) %></:value>
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

  def detail_list(assigns) do
    ~H"""
    <ul role="list" class={["divide-y divide-gray-200", @class]}>
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

  def state_pill(%{state: state} = assigns) do
    [text, classes] =
      case state do
        # only workorder states...
        :pending -> ["Pending", "bg-gray-200 text-gray-800"]
        :running -> ["Running", "bg-gray-200 text-gray-800"]
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
end
