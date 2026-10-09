defmodule LightningWeb.Components.Pills do
  @moduledoc """
  UI component to render a pill to create tags.
  """
  use Phoenix.Component
  import LightningWeb.Components.Icons
  alias Phoenix.LiveView.JS

  @doc """
  Renders a preview of a derived URL-safe name inside a yellow badge.

  Shows the badge only when the derived name is non-empty.

  ## Example

  ```heex
  <.name_badge name={@name} field={f[:name]}>
    Your project will be named
  </.name_badge>
  ```
  """
  attr :name, :string, required: true, doc: "The derived URL-safe name"

  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "The hidden :name field"

  slot :inner_block

  def name_badge(assigns) do
    ~H"""
    <span :if={to_string(@field.value) != ""}>
      {render_slot(@inner_block)}
      <span class="ml-1 rounded-md border border-slate-300 bg-yellow-100 p-1 font-mono text-xs">{@name}</span>.
    </span>
    """
  end

  @doc """
  A filter chip that acts as both a state display and a dropdown trigger.
  Gray when inactive, indigo when a filter is active.
  """
  attr :active, :boolean, default: false
  attr :clear_fields, :list, default: []
  attr :id, :string, required: true
  attr :target, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def filter_chip(assigns) do
    assigns = assign(assigns, :clear_js, build_clear_js(assigns))

    ~H"""
    <div
      id={@id}
      class={[
        "inline-flex items-center gap-x-1 rounded-full pl-3 text-sm font-medium transition-colors",
        if(@active,
          do: "bg-indigo-50 text-indigo-700 border border-indigo-200",
          else: "bg-gray-100 text-gray-700 border border-gray-200 hover:bg-gray-200"
        ),
        if(@active && @clear_fields != [],
          do: "pr-1.5",
          else: "pr-3"
        ),
        "py-1.5"
      ]}
    >
      <button type="button" class="cursor-pointer" {@rest}>
        {render_slot(@inner_block)}
      </button>
      <button
        :if={@active && @clear_fields != []}
        type="button"
        class="group flex items-center justify-center h-5 w-5 rounded-full hover:bg-indigo-200"
        aria-label="Clear filter"
        phx-click={@clear_js}
      >
        <.icon
          name="hero-x-mark-solid"
          class="h-3 w-3 text-indigo-400 group-hover:text-indigo-600"
        />
      </button>
    </div>
    """
  end

  defp build_clear_js(%{active: true, clear_fields: [_ | _]} = assigns) do
    clear_value =
      Map.new(assigns.clear_fields, fn
        {field_name, nil} -> {field_name, ""}
        {field_name, value} -> {field_name, value}
      end)

    opts = [value: %{filters: clear_value}]

    opts =
      if assigns[:target],
        do: opts ++ [target: assigns.target],
        else: opts

    JS.push("apply_filters", opts)
  end

  defp build_clear_js(_assigns), do: nil
end
