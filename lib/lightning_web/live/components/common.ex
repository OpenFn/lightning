defmodule LightningWeb.Components.Common do
  @moduledoc false
  use LightningWeb, :component

  import LightningWeb.Components.Icons

  alias Phoenix.LiveView.JS

  attr :id, :string, default: "alert"
  attr :type, :string, required: true
  attr :class, :string, default: ""
  attr :header, :string, default: nil
  slot :message
  attr :link_right, :map, required: false, default: nil
  attr :border, :boolean, default: false
  attr :action_position, :atom, default: :right
  attr :actions, :list, default: []

  @doc """
  Use an alert to convey critical information about the state of a specific
  system or artifact (a credential, a job, a workflow, etc.) and provide a type
  to indicate whether the alert is info, success, warning, or error.
  """
  def alert(assigns) do
    color =
      case assigns.type do
        "success" -> "green"
        "warning" -> "yellow"
        "danger" -> "red"
        _info -> "blue"
      end

    icon =
      case assigns.type do
        "success" -> "hero-check-circle-solid"
        "warning" -> "hero-exclamation-triangle-solid"
        "danger" -> "hero-x-circle-solid"
        _info -> "hero-information-circle-solid"
      end

    assigns =
      assign(assigns,
        color: color,
        icon: icon,
        class: assigns.class
      )

    ~H"""
    <div id={@id} class={"rounded-md bg-#{@color}-50 p-4 #{@class}"}>
      <div class="flex">
        <div class="flex-shrink-0">
          <.icon name={@icon} class={"h-5 w-5 text-#{@color}-400"} />
        </div>
        <div class={[
          "ml-3",
          assigns[:link_right] && "flex-1 md:flex md:justify-between"
        ]}>
          <%= if @header do %>
            <h3 class={"text-sm font-medium text-#{@color}-800"}><%= @header %></h3>
            <p class={"mt-2 text-sm text-#{@color}-700"}>
              <%= render_slot(@message) %>
            </p>
          <% else %>
            <p class={"text-sm text-#{@color}-700"}>
              <%= render_slot(@message) %>
            </p>
          <% end %>
          <%= if assigns[:link_right] do %>
            <p class="mt-3 text-sm md:ml-6 md:mt-0">
              <a
                href={@link_right.target}
                class={"whitespace-nowrap font-medium text-#{@color}-700 hover:text-#{@color}-600"}
              >
                <%= @link_right.text %>
                <span aria-hidden="true"> &rarr;</span>
              </a>
            </p>
          <% end %>
          <%= if Enum.count(@actions) > 0 do %>
            <div :if={@actions} class={["mt-4"]}>
              <div class="-mx-2 -my-1.5 flex">
                <%= for item <- @actions do %>
                  <%= case item do %>
                    <% %{id: id, text: text, click: click, target: target} -> %>
                      <button
                        id={id}
                        type="button"
                        phx-click={click}
                        phx-target={target}
                        class={"rounded-md bg-#{@color}-50 px-2 py-1.5 text-sm font-medium text-#{@color}-800 hover:bg-#{@color}-100 focus:outline-none focus:ring-2 focus:ring-#{@color}-600 focus:ring-offset-2 focus:ring-offset-#{@color}-50"}
                      >
                        <%= text %>
                      </button>
                    <% element -> %>
                      <%= element %>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, default: "banner"
  attr :type, :string, required: true
  attr :class, :string, default: ""
  attr :message, :string, required: true
  attr :action, :map, required: false, default: nil
  attr :dismissable, :boolean, default: false

  @doc """
  Banners can sometimes be dismissed, take the full width, and can optionally
  provide a link or button to perform a single action.
  """
  def banner(assigns) do
    classes =
      case assigns.type do
        "success" -> "alert-success"
        "warning" -> "alert-warning"
        "danger" -> "alert-danger"
        _info -> "alert-info"
      end

    assigns = assign(assigns, class: [classes] ++ List.wrap(assigns.class))

    ~H"""
    <div class={[
      "flex items-center gap-x-6 px-6 py-2.5 sm:px-3.5 sm:before:flex-1",
      @class
    ]}>
      <p class="text-sm leading-6">
        <%= @message %>
        <%= if assigns[:action] do %>
          <a href={@action.target} class="whitespace-nowrap font-semibold">
            <%= @action.text %>
            <span aria-hidden="true"> &rarr;</span>
          </a>
        <% end %>
      </p>
      <div class="flex flex-1 justify-end">
        <%!-- todo - add if/when we have a dismissable banner --%>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :version, :string, required: true
  attr :tooltip, :string, required: false

  def snapshot_version_chip(assigns) do
    styles =
      if assigns.version == "latest",
        do: "bg-blue-100 text-blue-800",
        else: "bg-yellow-100 text-yellow-800"

    has_tooltip? = Map.has_key?(assigns, :tooltip)

    assigns = assign(assigns, has_tooltip?: has_tooltip?, styles: styles)

    ~H"""
    <div id={"#{@id}-container"} class="flex items-baseline text-sm font-normal">
      <span
        id={@id}
        {if @has_tooltip?, do: ["phx-hook": "Tooltip", "data-placement": "bottom", "aria-label": @tooltip], else: []}
        class={"inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium #{@styles}"}
      >
        <%= @version %>
      </span>
    </div>
    """
  end

  attr :icon_classes, :string, default: "h-4 w-4 inline-block mr-1"

  def version_chip(assigns) do
    {display, message, type} =
      Lightning.release()
      |> case do
        %{image_tag: "edge"} = info ->
          {info.commit,
           "Docker image tag found: '#{info.image_tag}' unreleased build from #{info.commit} on #{info.branch}",
           :edge}

        %{image_tag: image} = info when not is_nil(image) ->
          {info.label,
           "Docker image tag found: '#{info.image_tag}' tagged release build from #{info.commit}",
           :release}

        info ->
          {info.label, "Lightning #{info.vsn}", :no_docker}
      end

    assigns =
      assign(assigns,
        display: display,
        message: message,
        type: type
      )

    ~H"""
    <div class="px-3 pb-3 rounded-md text-xs rounded-md block text-center">
      <span class="opacity-20" title={@message}>
        <%= case @type do %>
          <% :release -> %>
            <Heroicons.check_badge class={@icon_classes} />
          <% :edge -> %>
            <Heroicons.cube class={@icon_classes} />
          <% :warn -> %>
            <Heroicons.exclamation_triangle class={@icon_classes} />
          <% :no_docker -> %>
        <% end %>
      </span>
      <code
        class="px-2 py-1 opacity-20 bg-gray-100 rounded-md font-mono text-indigo-500 inline-block align-middle"
        title={"OpenFn/Lightning #{@display}"}
      >
        <%= @display %>
      </code>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: ""
  attr :icon, :string, default: "hero-information-circle-solid"
  attr :icon_class, :string, default: "w-4 h-4 text-primary-600 opacity-50"

  def tooltip(assigns) do
    classes = ~w"relative ml-1 cursor-pointer"

    assigns = assign(assigns, class: classes ++ List.wrap(assigns.class))

    ~H"""
    <span class={@class} id={@id} aria-label={@title} phx-hook="Tooltip">
      <.icon name={@icon} class={@icon_class} />
    </span>
    """
  end

  attr :id, :string, required: true
  attr :tooltip, :string, default: nil
  slot :inner_block, required: true

  def wrapper_tooltip(%{tooltip: tooltip} = assigns)
      when not is_nil(tooltip) do
    ~H"""
    <span
      id={"#{@id}-tooltip"}
      phx-hook="Tooltip"
      aria-label={@tooltip}
      data-allow-html="true"
    >
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  attr :text, :string, required: false
  slot :inner_block, required: false
  attr :disabled, :boolean, default: false
  attr :color, :string, default: "primary", values: ["primary", "red", "green"]
  attr :type, :string, default: "button", values: ["button", "submit"]
  attr :rest, :global

  def button(assigns) do
    class =
      button_classes(
        state: if(assigns.disabled, do: :inactive, else: :active),
        color: assigns.color
      )

    assigns =
      assigns
      |> assign(:class, class)
      |> update(:rest, fn rest, %{disabled: disabled} ->
        Map.merge(rest, %{disabled: disabled})
      end)

    ~H"""
    <button type={@type} class={@class} {@rest}>
      <%= if assigns.inner_block |> Enum.any?(),
        do: render_slot(@inner_block),
        else: @text %>
    </button>
    """
  end

  def button_white(assigns) do
    class = ~w[
      inline-flex items-center justify-center px-4 py-2 border
      border-gray-300 rounded-md shadow-sm
      text-sm font-medium text-gray-700
      bg-white hover:bg-gray-50
      focus:outline-none
      focus:ring-2
      focus:ring-offset-2
      focus:ring-indigo-500
    ]

    extra = assigns_to_attributes(assigns, [:disabled, :text])

    assigns =
      assign_new(assigns, :disabled, fn -> false end)
      |> assign_new(:onclick, fn -> nil end)
      |> assign_new(:title, fn -> nil end)
      |> assign(:class, class)
      |> assign(:extra, extra)

    ~H"""
    <button type="button" class={@class} onclick={@onclick} title={@title} {@extra}>
      <%= if assigns[:inner_block], do: render_slot(@inner_block), else: @text %>
    </button>
    """
  end

  defp button_classes(state: state, color: color) do
    base_classes = ~w[
      inline-flex
      justify-center
      py-2
      px-4
      border
      border-transparent
      shadow-sm
      text-sm
      font-medium
      rounded-md
      text-white
      focus:outline-none
      focus:ring-2
      focus:ring-offset-2
    ]

    case {state, color} do
      {:active, "primary"} ->
        ~w[focus:ring-primary-500 bg-primary-600 hover:bg-primary-700] ++
          base_classes

      {:inactive, "primary"} ->
        ~w[focus:ring-primary-500 bg-primary-300] ++ base_classes

      {:active, "red"} ->
        ~w[focus:ring-red-500 bg-red-600 hover:bg-red-700] ++
          base_classes

      {:inactive, "red"} ->
        ~w[focus:ring-red-500 bg-red-300] ++ base_classes

      {:active, "green"} ->
        ~w[focus:ring-green-500 bg-green-600 hover:bg-green-700] ++ base_classes

      {:inactive, "green"} ->
        ~w[focus:ring-green-500 bg-green-400] ++ base_classes
    end
  end

  def flash(%{kind: :error} = assigns) do
    ~H"""
    <div
      :if={msg = live_flash(@flash, @kind)}
      id="flash"
      class="rounded-md bg-red-200 border-red-300 p-4 fixed w-fit mx-auto flex justify-center bottom-3 right-0 left-0 z-[100]"
      phx-click={
        JS.push("lv:clear-flash")
        |> JS.remove_class("fade-in-scale", to: "#flash")
        |> hide("#flash")
      }
      phx-hook="Flash"
    >
      <div class="flex justify-between items-center space-x-3 text-red-900">
        <Heroicons.exclamation_circle solid class="w-5 h-5" />
        <p class="flex-1 text-sm font-medium" role="alert">
          <%= msg %>
        </p>
        <button
          type="button"
          class="inline-flex bg-red-200 rounded-md p-1.5 text-red-500 hover:bg-red-400 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-red-50 focus:ring-red-800"
        >
          <Heroicons.x_mark
            solid
            class="w-4 h-4 ml-1 mr-1 text-white-400 dark:text-white-100"
          />
        </button>
      </div>
    </div>
    """
  end

  def flash(%{kind: :info} = assigns) do
    ~H"""
    <div
      :if={msg = live_flash(@flash, @kind)}
      id="flash"
      class="rounded-md bg-blue-200 border-blue-300 rounded-md p-4 fixed w-fit mx-auto flex justify-center bottom-3 right-0 left-0 z-[100]"
      phx-click={
        JS.push("lv:clear-flash")
        |> JS.remove_class("fade-in-scale")
        |> hide("#flash")
      }
      phx-value-key="info"
      phx-hook="Flash"
    >
      <div class="flex justify-between items-center space-x-3 text-blue-900">
        <Heroicons.check_circle solid class="w-5 h-5" />
        <p class="flex-1 text-sm font-medium" role="alert">
          <%= msg %>
        </p>
        <button
          type="button"
          class="inline-flex bg-blue-200 rounded-md p-1.5 text-blue-500 hover:bg-blue-400 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-blue-200 focus:ring-blue-800"
        >
          <Heroicons.x_mark
            solid
            class="w-4 h-4 ml-1 mr-1 text-white-400 dark:text-white-100"
          />
        </button>
      </div>
    </div>
    """
  end

  defp hide(js, selector) do
    JS.hide(js,
      to: selector,
      time: 300,
      transition:
        {"transition ease-in duration-300", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
  end

  attr :type, :atom,
    required: true,
    values: [:step_result, :http_request, :global, :saved_input]

  def dataclip_type_pill(assigns) do
    base_classes = ~w[
      px-2 py-1 rounded-full inline-block text-sm font-mono
    ]

    class =
      base_classes ++
        case assigns[:type] do
          :step_result -> ~w[bg-purple-500 text-purple-900]
          :http_request -> ~w[bg-green-500 text-green-900]
          :global -> ~w[bg-blue-500 text-blue-900]
          :saved_input -> ~w[bg-yellow-500 text-yellow-900]
          _other -> []
        end

    assigns = assign(assigns, class: class)

    ~H"""
    <div class={@class}>
      <%= @type %>
    </div>
    """
  end
end
