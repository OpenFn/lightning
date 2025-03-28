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
end
