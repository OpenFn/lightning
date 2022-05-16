defmodule LightningWeb.Components.Settings do
  @moduledoc """
  Components for Settings live session
  """
  use LightningWeb, :component

  def menu_item(assigns) do
    base_classes = ~w[
      m-4 px-3 py-2 rounded-md text-sm font-medium rounded-md block
    ]

    active_classes = ~w[text-indigo-200 bg-indigo-900] ++ base_classes
    inactive_classes = ~w[text-indigo-300 hover:bg-indigo-900] ++ base_classes

    ~H"""
    <%= live_redirect(@text,
      to: @to,
      class: if(@active, do: active_classes, else: inactive_classes)
    ) %>
    """
  end
end
