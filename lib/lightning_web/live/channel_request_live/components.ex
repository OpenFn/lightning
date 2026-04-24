defmodule LightningWeb.ChannelRequestLive.Components do
  @moduledoc """
  Reusable function components for the channel request detail page.

  Provides layout primitives (disclosure sections), HTTP display atoms
  (method badges, status codes), and content viewers (headers, body)
  used across multiple sections.
  """

  use LightningWeb, :component

  import LightningWeb.RunLive.Components, only: [channel_state_pill: 1]

  alias LightningWeb.ChannelRequestLive.Helpers
  alias Phoenix.LiveView.JS

  # --- Layout primitives ---

  def disclosure_section(assigns) do
    assigns =
      assigns
      |> assign_new(:title_right, fn -> [] end)
      |> assign_new(:padded, fn -> true end)

    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-secondary-200">
      <button
        type="button"
        class="w-full flex items-center justify-between p-4 text-left cursor-pointer"
        phx-click={
          JS.toggle(to: "##{@id}-content")
          |> JS.toggle_class("rotate-180", to: "##{@id}-chevron")
        }
      >
        <div class="flex items-center gap-3">
          <h3 class="text-sm font-semibold text-secondary-900">{@title}</h3>
          {render_slot(@title_right)}
        </div>
        <.icon
          id={"#{@id}-chevron"}
          name="hero-chevron-down-mini"
          class={[
            "h-5 w-5 text-secondary-400 transition-transform",
            unless(@open, do: "rotate-180")
          ]}
        />
      </button>
      <div
        id={"#{@id}-content"}
        class={[
          if(@padded, do: "px-4 pb-4"),
          unless(@open, do: "hidden")
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def sub_section(assigns) do
    assigns = assign_new(assigns, :title_right, fn -> [] end)

    ~H"""
    <div class="border-t border-secondary-100">
      <button
        type="button"
        class="w-full px-4 py-2.5 flex items-center justify-between cursor-pointer"
        phx-click={
          JS.toggle(to: "##{@id}-content")
          |> JS.toggle_class("rotate-180", to: "##{@id}-chevron")
        }
      >
        <div class="flex items-center gap-2">
          <span class="text-xs font-medium text-secondary-500 uppercase tracking-wider">
            {@title}
          </span>
          {render_slot(@title_right)}
        </div>
        <.icon
          id={"#{@id}-chevron"}
          name="hero-chevron-down-mini"
          class={[
            "h-4 w-4 text-secondary-400 transition-transform",
            unless(@open, do: "rotate-180")
          ]}
        />
      </button>
      <div id={"#{@id}-content"} class={["px-4 pb-3", unless(@open, do: "hidden")]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # --- HTTP display atoms ---

  def method_badge(assigns) do
    color_class =
      case assigns.method do
        "GET" -> "bg-blue-100 text-blue-800"
        "POST" -> "bg-green-100 text-green-800"
        "PUT" -> "bg-amber-100 text-amber-800"
        "PATCH" -> "bg-amber-100 text-amber-800"
        "DELETE" -> "bg-red-100 text-red-800"
        _ -> "bg-secondary-100 text-secondary-800"
      end

    assigns = assign(assigns, color_class: color_class)

    ~H"""
    <span
      id="method-badge"
      class={[
        "inline-flex items-center px-2.5 py-0.5 rounded text-sm font-bold font-mono uppercase",
        @color_class
      ]}
    >
      {@method || "—"}
    </span>
    """
  end

  def request_path_display(assigns) do
    ~H"""
    <span class="font-mono text-sm break-all">
      <span class="text-secondary-900">{@event && @event.request_path}</span>
      <span
        :if={
          @event && @event.request_query_string && @event.request_query_string != ""
        }
        class="text-secondary-400"
      >
        ?{@event.request_query_string}
      </span>
    </span>
    """
  end

  def status_code_display(assigns) do
    color_class =
      cond do
        is_nil(assigns.status) -> "text-secondary-400"
        assigns.status >= 500 -> "text-red-700 bg-red-50"
        assigns.status >= 400 -> "text-amber-700 bg-amber-50"
        assigns.status >= 300 -> "text-blue-700 bg-blue-50"
        assigns.status >= 200 -> "text-green-700 bg-green-50"
        true -> "text-secondary-400"
      end

    assigns = assign(assigns, color_class: color_class)

    ~H"""
    <span class={["font-mono text-sm font-bold px-1.5 py-0.5 rounded", @color_class]}>
      {if @status, do: to_string(@status), else: "—"}
    </span>
    """
  end

  def status_code_badge(assigns) do
    color_class =
      case assigns.status do
        s when s >= 200 and s < 300 -> "bg-green-100 text-green-700"
        s when s >= 300 and s < 400 -> "bg-blue-100 text-blue-700"
        s when s >= 400 and s < 500 -> "bg-amber-100 text-amber-700"
        s when s >= 500 -> "bg-red-100 text-red-700"
        _ -> "bg-secondary-100 text-secondary-700"
      end

    assigns = assign(assigns, color_class: color_class)

    ~H"""
    <span class={[
      "inline-flex items-center rounded px-1.5 py-0.5 text-xs font-mono font-bold",
      @color_class
    ]}>
      {@status}
    </span>
    """
  end

  def state_pill_with_tooltip(assigns) do
    ~H"""
    <%= if @state == :timeout and @error_message do %>
      <Common.wrapper_tooltip
        id="state-pill-tooltip"
        tooltip={Helpers.humanize_error(@error_message)}
      >
        <.channel_state_pill state={@state} />
      </Common.wrapper_tooltip>
    <% else %>
      <.channel_state_pill state={@state} />
    <% end %>
    """
  end

  def response_empty(assigns) do
    {icon, label} =
      case assigns.type do
        :transport ->
          {"hero-exclamation-triangle", "No response received"}

        :credential ->
          {"hero-lock-closed", "Request not sent — credential error"}
      end

    assigns = assign(assigns, icon: icon, label: label)

    ~H"""
    <div class="border-t border-secondary-100">
      <div class="flex flex-col items-center justify-center px-4 py-8 text-secondary-500">
        <.icon name={@icon} class="h-8 w-8 mb-3 text-secondary-400" />
        <p class="font-medium mb-1">{@label}</p>
        <p class="text-sm mb-2">{@human_message}</p>
        <code class="text-xs font-mono bg-secondary-100 px-2 py-1 rounded">
          {@error_code}
        </code>
      </div>
    </div>
    """
  end

  # --- Content display ---

  def headers_table(assigns) do
    ~H"""
    <table class="w-full text-xs">
      <tbody class="divide-y divide-secondary-50">
        <tr :for={[name, value] <- @headers}>
          <td class="py-1.5 pr-3 text-secondary-500 font-medium whitespace-nowrap align-top w-1/3">
            {name}
          </td>
          <td class={[
            "py-1.5 font-mono break-all",
            if(value == "[REDACTED]",
              do: "italic text-secondary-400",
              else: "text-secondary-700"
            )
          ]}>
            {value}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  def body_viewer(assigns) do
    content_type = Helpers.extract_content_type(assigns.headers)
    is_binary_content = content_type && !Helpers.text_content_type?(content_type)

    no_body =
      assigns.body_size == 0 and
        (is_nil(assigns.body_preview) or assigns.body_preview == "")

    assigns =
      assign(assigns,
        content_type: content_type,
        is_binary_content: is_binary_content,
        no_body: no_body
      )

    ~H"""
    <%= cond do %>
      <% @no_body -> %>
        <div id={@id} class="py-6 flex flex-col items-center text-secondary-400">
          <.icon name="hero-document" class="h-6 w-6 mb-1 text-secondary-300" />
          <span class="text-xs">No body</span>
        </div>
      <% @is_binary_content -> %>
        <div id={@id} class="py-4 text-sm text-secondary-500">
          <span class="text-xs font-mono bg-secondary-100 px-1.5 py-0.5 rounded">
            {Helpers.format_content_type_label(@content_type)}
          </span>
          <span :if={@body_size} class="ml-2">
            {Helpers.format_bytes(@body_size)}
          </span>
          <span :if={@body_hash} class="ml-2 font-mono text-xs text-secondary-400">
            SHA256: {@body_hash}
          </span>
        </div>
      <% is_nil(@body_preview) -> %>
        <div id={@id} class="py-4 text-sm text-secondary-500">
          Body not captured
          <span :if={@body_size} class="text-xs text-secondary-400 ml-1">
            ({Helpers.format_bytes(@body_size)})
          </span>
        </div>
      <% true -> %>
        <div id={@id}>
          <div class="relative rounded-md bg-secondary-50 border border-secondary-200">
            <div class="absolute top-2 right-2 flex items-center gap-1.5">
              <span
                :if={@content_type}
                class="text-[10px] font-mono text-secondary-400 bg-white/80 rounded px-1.5 py-0.5"
              >
                {Helpers.format_content_type_label(@content_type)}
              </span>
              <.copy_icon_button
                id={"#{@id}-copy"}
                value={@body_preview}
                title="Copy body"
                size={3}
                class="p-1 bg-white/80 rounded"
              />
            </div>
            <pre class="text-xs font-mono p-3 pr-20 max-h-80 overflow-auto text-secondary-700 whitespace-pre-wrap break-all">{@body_preview}</pre>
          </div>
          <div
            :if={@body_hash}
            class="mt-2 flex items-center gap-2 text-[11px] text-secondary-400"
          >
            <span class="font-mono">
              SHA256: {String.slice(@body_hash, 0..15)}...
            </span>
            <.copy_icon_button
              id={"#{@id}-hash-copy"}
              value={@body_hash}
              title="Copy hash"
              size={3}
            />
          </div>
          <div
            :if={
              @body_size && @body_preview && @body_size > byte_size(@body_preview)
            }
            class="mt-1 text-[11px] text-secondary-400"
          >
            Preview: {Helpers.format_bytes(byte_size(@body_preview))} of {Helpers.format_bytes(
              @body_size
            )}
          </div>
        </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :title, :string, default: "Copy"
  attr :size, :integer, default: 4
  attr :class, :string, default: nil

  def copy_icon_button(assigns) do
    ~H"""
    <button
      id={@id}
      phx-hook="Copy"
      data-content={@value}
      class={[
        "copy-btn text-secondary-400 hover:text-secondary-600 transition-colors shrink-0 cursor-pointer",
        @class
      ]}
      title={@title}
    >
      <.icon name="hero-clipboard" class={"h-#{@size} w-#{@size}"} />
    </button>
    """
  end

  def section_size_badge(assigns) do
    ~H"""
    <span id={@id} class="text-xs text-secondary-400 font-mono">
      {Helpers.format_bytes(@size)}
    </span>
    """
  end
end
