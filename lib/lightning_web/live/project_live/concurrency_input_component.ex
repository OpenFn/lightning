defmodule LightningWeb.ProjectLive.ConcurrencyInputComponent do
  use LightningWeb, :live_component

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:max_value, nil)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.input
        type="integer-toggle"
        field={@field}
        disabled={@disabled}
        label=""
        max_value={@max_value}
      />
    </div>
    """
  end
end
