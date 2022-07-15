defmodule LightningWeb.Components.Common do
  @moduledoc """
  Common Components
  """
  use LightningWeb, :component

  def button(assigns) do
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
      focus:ring-primary-500
    ]

    active_classes = ~w[
      bg-primary-600
      hover:bg-primary-700
    ] ++ base_classes

    inactive_classes = ~w[
      bg-primary-300
    ] ++ base_classes

    class =
      if assigns[:disabled] do
        inactive_classes
      else
        active_classes
      end

    extra = assigns_to_attributes(assigns, [:disabled, :text])

    assigns =
      Phoenix.LiveView.assign_new(assigns, :disabled, fn -> false end)
      |> Phoenix.LiveView.assign_new(:onclick, fn -> nil end)
      |> Phoenix.LiveView.assign_new(:title, fn -> nil end)
      |> assign(:class, class)
      |> assign(:extra, extra)

    ~H"""
    <button
      type="button"
      class={@class}
      disabled={@disabled}
      onclick={@onclick}
      title={@title}
      {@extra}
    >
      <%= if assigns[:inner_block], do: render_slot(@inner_block), else: @text %>
    </button>
    """
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

  # https://play.tailwindcss.com/r7kBDT2cJY?layout=horizontal
  def page_content(assigns) do
    ~H"""
    <div class="flex h-full w-full flex-col">
      <%= render_slot(@header) %>
      <div class="flex-auto bg-secondary-100 relative">
        <div class="overflow-y-auto absolute top-0 bottom-0 left-0 right-0">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  def header(assigns) do
    ~H"""
    <div class="flex-none bg-white shadow-sm z-10">
      <div class="max-w-7xl mx-auto h-20 sm:px-6 lg:px-8 flex items-center">
        <h1 class="text-3xl font-bold text-secondary-900">
          <%= @title %>
        </h1>
        <div class="grow"></div>
        <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end
