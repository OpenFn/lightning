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
end
