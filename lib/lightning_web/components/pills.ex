defmodule LightningWeb.Components.Pills do
  @moduledoc """
  UI component to render a pill to create tags.
  """
  use Phoenix.Component

  @doc """
  Renders a pill with a color.

  ## Example

  ```
  <.pill color="red">
    Red pill
  </.pill>
  ```

  ## Colors

  - `gray` **default**
  - `red`
  - `yellow`
  - `green`
  - `blue`
  - `indigo`
  - `purple`
  - `pink`
  """
  attr :color, :string,
    default: "gray",
    values: [
      "gray",
      "red",
      "yellow",
      "green",
      "blue",
      "indigo",
      "purple",
      "pink"
    ]

  slot :inner_block, required: true
  attr :rest, :global

  def pill(assigns) do
    assigns =
      assigns
      |> assign(
        class:
          case assigns[:color] do
            "gray" -> "bg-gray-100 text-gray-600"
            "red" -> "bg-red-100 text-red-700"
            "yellow" -> "bg-yellow-100 text-yellow-800"
            "green" -> "bg-green-100 text-green-700"
            "blue" -> "bg-blue-100 text-blue-700"
            "indigo" -> "bg-indigo-100 text-indigo-700"
            "purple" -> "bg-purple-100 text-purple-700"
            "pink" -> "bg-pink-100 text-pink-700"
          end
      )

    ~H"""
    <span
      class={[
        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

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
end
