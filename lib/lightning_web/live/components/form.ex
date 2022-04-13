defmodule LightningWeb.Components.Form do
  @moduledoc """
  Form Components
  """
  use LightningWeb, :component

  def submit_button(assigns) do
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

    inactive_classes = ~w[
      bg-indigo-300
    ] ++ base_classes

    active_classes = ~w[
      bg-indigo-600
      hover:bg-indigo-700
    ] ++ base_classes

    ~H"""
      <%= submit "Save",
        phx_disable_with: "Saving...",
        disabled: !@changeset.valid?,
        class: if @changeset.valid?, do: active_classes, else: inactive_classes %>
    """
  end
end
