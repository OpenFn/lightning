defmodule LightningWeb.Components.Icon do
  @moduledoc false

  # For Lightning-specific concepts, we define icons here for ease of management
  # and reuse.
  #
  # Note: we're in the process of migrating away from defining SVGs here and
  # instead using Heroicons from Petal.

  use LightningWeb, :component

  @spec dataclip_icon_color(atom) :: String.t() | nil
  def dataclip_icon_color(type) do
    case type do
      :step_result -> "bg-purple-500 text-purple-900"
      :http_request -> "bg-green-500 text-green-900"
      :global -> "bg-blue-500 text-blue-900"
      :saved_input -> "bg-yellow-500 text-yellow-900"
      _ -> nil
    end
  end

  @spec dataclip_icon_class(atom) :: String.t() | nil
  def dataclip_icon_class(type) do
    case type do
      :saved_input -> "hero-pencil-square"
      :global -> "hero-globe-alt"
      :step_result -> "hero-document-text"
      :http_request -> "hero-document-arrow-down"
      nil -> nil
    end
  end

  def workflows(assigns), do: Heroicons.square_3_stack_3d(assigns)

  def runs(assigns), do: Heroicons.rectangle_stack(assigns)

  def pencil(assigns), do: Heroicons.pencil(assigns)

  def exclamation_circle(assigns), do: Heroicons.exclamation_circle(assigns)

  def settings(assigns), do: Heroicons.cog_8_tooth(assigns)

  def dataclips(assigns), do: Heroicons.cube(assigns)

  def info(assigns), do: Heroicons.information_circle(assigns)

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

  def right(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M13 7l5 5m0 0l-5 5m5-5H6"
      />
    </.outer_svg>
    """
  end

  def trash(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
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

  def plus_circle(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
        class="w-6 h-6"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M12 9v6m3-3H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
    </.outer_svg>
    """
  end

  def eye(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
      />
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
      />
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
      <%= render_slot(@inner_block) %>
    </svg>
    """
  end

  defp build_attrs(assigns, default_classes) do
    assigns
    |> Map.put_new(:class, default_classes)
    |> assigns_to_attributes()
  end
end
