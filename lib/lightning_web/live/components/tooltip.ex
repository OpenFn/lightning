defmodule LightningWeb.Components.Tooltip do
  @moduledoc false

  # For Lightning-specific concepts, we define tooltips here for ease of management
  # and reuse.

  use LightningWeb, :component

  def top(assigns) do
    ~H"""
    <div>Top tooltip</div>
    """
  end
end
