defmodule LightningWeb.Components.Common do
  @moduledoc false
  use LightningWeb, :component

  alias Phoenix.LiveView.JS

  def version_chip(assigns) do
    image_info = Application.get_env(:lightning, :image_info)
    image = image_info[:image_tag]
    branch = image_info[:branch]
    commit = image_info[:commit]
    vsn = "v#{Application.spec(:lightning, :vsn)}"

    {display, message, type} =
      cond do
        # If running in docker on edge, display commit SHA.
        image == "edge" ->
          {commit,
           "Docker image tag found: '#{image}' unreleased build from #{commit} on #{branch}",
           :edge}

        # If running in docker and tag matches :vsn, display :vsn and standard message.
        image == vsn ->
          {vsn,
           "Docker image tag found: '#{image}' tagged release build from #{commit}",
           :release}

        # If running in docker and tag doesn't match :vsn, display image tag.
        image != nil and image != vsn and image != "edge" ->
          {image,
           "Detected image tag that does not match application version #{vsn}; image tag '#{image}' built from #{commit}",
           :warn}

        # If running in docker and tag doesn't match :vsn, display commit.
        image != nil and image != vsn ->
          {commit,
           "Detected image tag that does not match application version #{vsn}; image tag '#{image}' built from #{commit}",
           :warn}

        true ->
          {vsn, "Lightning #{vsn}", :no_docker}
      end

    icon_classes = "h-4 w-4 inline-block mr-1"

    assigns =
      assign(assigns,
        display: display,
        message: message,
        type: type,
        icon_classes: icon_classes
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

  def tooltip(assigns) do
    classes = ~w"
      relative ml-1 cursor-pointer
    "

    assigns = assign(assigns, class: classes ++ List.wrap(assigns.class))

    ~H"""
    <span class={@class} id={@id} aria-label={@title} phx-hook="Tooltip">
      <Heroicons.information_circle
        solid
        class="w-4 h-4 text-primary-600 opacity-50"
      />
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

  def item_bar(assigns) do
    base_classes = ~w[
      w-full rounded-md drop-shadow-sm
      outline-2 outline-blue-300
      bg-white flex mb-4
      hover:outline hover:drop-shadow-none
    ]

    assigns = Map.merge(%{id: nil, class: base_classes}, assigns)

    ~H"""
    <div class={@class} id={@id}>
      <%= render_slot(@inner_block) %>
    </div>
    """
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
    values: [:run_result, :http_request, :global, :saved_input]

  def dataclip_type_pill(assigns) do
    base_classes = ~w[
      px-2 py-1 rounded-full inline-block text-sm font-mono
    ]

    class =
      base_classes ++
        case assigns[:type] do
          :run_result -> ~w[bg-purple-500 text-purple-900]
          :http_request -> ~w[bg-green-500 text-green-900]
          :global -> ~w[bg-blue-500 text-blue-900]
          :saved_input -> ~w[bg-yellow-500 text-yellow-900]
          _ -> []
        end

    assigns = assign(assigns, class: class)

    ~H"""
    <div class={@class}>
      <%= @type %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :default_hash, :string, required: true
  attr :orientation, :string, required: true, values: ["horizontal", "vertical"]
  slot :inner_block, required: true

  def tab_bar(assigns) do
    assigns =
      assigns
      |> assign(
        class:
          case assigns[:orientation] do
            "horizontal" ->
              ~w[border-b border-gray-200 dark:border-gray-600 flex gap-x-4 gap-y-2]

            "vertical" ->
              ~w[flex flex-col flex-wrap gap-y-2 list-none mr-4 nav nav-tabs]
          end
      )

    ~H"""
    <div
      id={"tab-bar-#{@id}"}
      class={@class}
      data-active-classes="border-b-2 border-primary-500 text-primary-600"
      data-inactive-classes="border-b-2 border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-600 hover:border-gray-300"
      data-disabled-classes="border-b-2 border-transparent text-gray-500 hover:cursor-not-allowed"
      data-default-hash={@default_hash}
      phx-hook="TabSelector"
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :for_hash, :string, required: true
  slot :inner_block, required: true

  def panel_content(assigns) do
    ~H"""
    <div
      class="h-[calc(100%-0.4rem)]"
      data-panel-hash={@for_hash}
      style="display: none;"
      lv-keep-style
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :hash, :string, required: true
  attr :orientation, :string, required: true, values: ["horizontal", "vertical"]
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  def tab_item(assigns) do
    assigns =
      assigns
      |> assign(
        base_classes: ~w[
          border-b-2
          border-transparent
          font-medium
          text-gray-500
          text-sm
        ],
        orientation_classes:
          case assigns[:orientation] do
            "horizontal" -> ~w[
              px-2
              py-2
            ]
            "vertical" -> ~w[
              flex
              items-center
              px-3
              py-3
              whitespace-nowrap
            ]
          end,
        disabled_classes: ~w[hover:cursor-not-allowed],
        enabled_classes: ~w[
          hover:border-gray-300
          hover:border-gray-300
          hover:text-gray-600
        ]
      )

    ~H"""
    <%= if @disabled do %>
      <span
        id={"tab-item-#{@hash}"}
        class={[@base_classes, @orientation_classes, @disabled_classes]}
        data-disabled
        data-hash={@hash}
        lv-keep-class
      >
        <%= render_slot(@inner_block) %>
      </span>
    <% else %>
      <a
        id={"tab-item-#{@hash}"}
        class={[@base_classes, @orientation_classes, @enabled_classes]}
        data-hash={@hash}
        lv-keep-class
        phx-click={switch_tabs(@hash)}
        href={"##{@hash}"}
      >
        <%= render_slot(@inner_block) %>
      </a>
    <% end %>
    """
  end

  defp switch_tabs(hash) do
    JS.hide(to: "[data-panel-hash]:not([data-panel-hash=#{hash}])")
    |> JS.show(
      to: "[data-panel-hash=#{hash}]",
      transition: {"ease-in duration-150 delay-50", "opacity-0", "opacity-100"},
      time: 200
    )
  end
end
