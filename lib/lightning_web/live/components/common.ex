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
      focus:ring-indigo-500
    ]

    active_classes = ~w[
      bg-indigo-600
      hover:bg-indigo-700
    ] ++ base_classes

    ~H"""
    <button class={active_classes}><%= @text %></button>
    """
  end
end
