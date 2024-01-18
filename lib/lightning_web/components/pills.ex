defmodule LightningWeb.Components.Pills do
  @moduledoc """
  UI component to render a pill to create tags.
  """
  use Phoenix.Component

  slot :inner_block, required: true

  def pill(assigns) do
    ~H"""
    <span class={~w[
      my-auto whitespace-nowrap rounded-full
      py-2 px-4 text-center align-baseline text-xs font-medium leading-none
    ]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end
end
