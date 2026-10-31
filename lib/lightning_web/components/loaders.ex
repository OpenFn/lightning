defmodule LightningWeb.Components.Loaders do
  @moduledoc """
  Loading indicators.
  """
  use Phoenix.Component

  slot :inner_block, required: true

  def text_ping_loader(assigns) do
    ~H"""
    <span class="relative inline-flex">
      <div class="inline-flex">
        {render_slot(@inner_block)}
      </div>
      <span class="flex absolute h-3 w-3 right-0 -mr-5">
        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary-400 opacity-75">
        </span>
        <span class="relative inline-flex rounded-full h-3 w-3 bg-primary-500">
        </span>
      </span>
    </span>
    """
  end
end
