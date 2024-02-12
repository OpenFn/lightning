defmodule LightningWeb.Components.Loaders do
  @moduledoc """
  UI component to render a pill to create tags.
  """
  use Phoenix.Component

  slot :inner_block, required: true

  def text_ping_loader(assigns) do
    ~H"""
    <span class="relative inline-flex">
      <div class="inline-flex">
        <%= render_slot(@inner_block) %>
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

  slot :inner_block, required: true

  def button_loader(assigns) do
    ~H"""
    <span class="relative inline-flex">
      <button
        type="button"
        class="inline-flex items-center px-4 py-2 font-semibold leading-6
            text-sm shadow rounded-md bg-white dark:bg-slate-800
            transition ease-in-out duration-150 cursor-not-allowed ring-1
            ring-slate-900/10 dark:ring-slate-200/20"
        disabled=""
      >
        <%= render_slot(@inner_block) %>
      </button>
      <span class="flex absolute h-3 w-3 top-0 right-0 -mt-1 -mr-1">
        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary-400 opacity-75">
        </span>
        <span class="relative inline-flex rounded-full h-3 w-3 bg-primary-500">
        </span>
      </span>
    </span>
    """
  end
end
