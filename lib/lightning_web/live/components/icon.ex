defmodule LightningWeb.Components.Icon do
  @moduledoc false

  # For Lightning-specific concepts, we define icons here for ease of management
  # and reuse.
  #
  # Note: we're in the process of migrating away from defining SVGs here and
  # instead using Heroicons.

  use LightningWeb, :component

  def workflows(assigns), do: Heroicons.square_3_stack_3d(assigns)

  def sandboxes(assigns), do: Heroicons.beaker(assigns)

  def channels(assigns), do: Heroicons.arrows_right_left(assigns)

  def branches(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      class={@class}
      aria-hidden="true"
    >
      <circle cx="6" cy="6" r="2.25" />
      <circle cx="18" cy="6" r="2.25" />
      <circle cx="18" cy="18" r="2.25" />
      <path d="M6 8v10a4 4 0 0 0 4 4h8" />
      <path d="M8 6h8" />
    </svg>
    """
  end

  def runs(assigns), do: Heroicons.rectangle_stack(assigns)

  def settings(assigns), do: Heroicons.cog_8_tooth(assigns)

  def left(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M11 17l-5-5m0 0l5-5m-5 5h12"
      />
    </.outer_svg>
    """
  end

  def plus(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
    </.outer_svg>
    """
  end

  def chevron_left(assigns) do
    ~H"""
    <svg
      class="h-5 w-5"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
    >
      <path
        fill-rule="evenodd"
        d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  def chevron_right(assigns) do
    ~H"""
    <svg
      class="h-5 w-5"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
    >
      <path
        fill-rule="evenodd"
        d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp outer_svg(assigns) do
    default_classes = ~w[h-5 w-5 inline-block]
    assigns = assign(assigns, attrs: build_attrs(assigns, default_classes))

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
      {@attrs}
    >
      {render_slot(@inner_block)}
    </svg>
    """
  end

  defp build_attrs(assigns, default_classes) do
    assigns
    |> Map.put_new(:class, default_classes)
    |> assigns_to_attributes()
  end
end
