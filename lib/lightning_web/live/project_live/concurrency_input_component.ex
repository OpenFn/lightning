defmodule LightningWeb.ProjectLive.ConcurrencyInputComponent do
  use LightningWeb, :live_component

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center">
      <.input
        type="integer-toggle"
        field={@field}
        disabled={@disabled}
        label=""
        max={nil}
      />
      <span class="ml-3 text-sm" id="concurrency-description">
        <span class="font-medium text-gray-900">Disable parallel execution</span>
        <span class="text-gray-500">
          (No more than one run at a time)
        </span>
      </span>
    </div>
    """
  end
end
