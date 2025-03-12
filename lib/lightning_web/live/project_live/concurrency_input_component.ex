defmodule LightningWeb.ProjectLive.ConcurrencyInputComponent do
  use LightningWeb, :live_component

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.input
        type="integer-toggle"
        field={@field}
        disabled={@disabled}
        label=""
        max={nil}
      />
      <span class="flex grow flex-col">
        <.label>Disable parallel run execution</.label>
        <span class="text-sm text-gray-500" id="concurrency-description">
          Process all runs in this project no more than one at a time.
        </span>
      </span>
    </div>
    """
  end
end
