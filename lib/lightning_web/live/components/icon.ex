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
      :kafka -> "bg-green-500 text-green-900"
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
      :kafka -> "hero-document-arrow-down"
      nil -> nil
    end
  end

  def workflows(assigns), do: Heroicons.square_3_stack_3d(assigns)

  def sandboxes(assigns), do: Heroicons.beaker(assigns)

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

  def openfn_fn(assigns) do
    assigns = assign_new(assigns, :title, fn -> nil end)

    ~H"""
    <svg
      class={@class}
      viewBox="0 0 700 700"
      fill="currentColor"
      aria-label="OpenFn"
      xmlns="http://www.w3.org/2000/svg"
    >
      <title :if={@title}>{@title}</title>
      <rect
        style="fill:none;stroke:currentColor;stroke-width:26.7094"
        width="640.24908"
        height="642.35791"
        x="28.611572"
        y="28.596663"
      />
      <path d="m 151.76628,490.23609 -1.01302,-280.49701 168.58284,-0.5065 v 46.79003 l -114.54797,1.01299 0.5066,68.75169 110.88134,-0.50649 0.5066,46.77988 -111.38794,-1.01302 v 119.69493 z" />
      <path d="m 480.9654,295.73156 c -10.1885,0.68592 -20.44341,1.34598 -30.41004,3.70627 -6.7186,1.94448 -12.55839,6.00825 -17.94746,10.3457 -4.0239,3.50043 -8.79018,7.97649 -11.79238,11.87526 -0.82513,1.0716 -2.13901,3.00532 -3.60003,3.56352 -0.69924,0.26722 -1.32289,-3.29391 -1.44674,-4.43277 -0.4806,-7.15734 -0.88323,-14.32125 -1.33376,-21.48113 -1.77223,-1.0828 -3.9031,-0.45183 -5.84641,-0.58066 -14.95206,-0.13811 -29.90462,-0.11296 -44.85685,-0.11619 V 490.5945 l 52.8698,-0.50767 c 0,-37.0417 0.017,-74.08342 0.0238,-111.12514 0.78758,-15.67674 5.22819,-27.24547 14.88239,-36.16377 3.20761,-3.02955 7.26649,-5.06141 11.54537,-6.07242 4.94721,-1.2738 10.09065,-1.50683 15.17665,-1.53868 4.84256,0.0827 9.76939,0.57924 14.31822,2.33231 4.76969,2.08259 8.70812,5.63037 12.26347,9.35691 3.1534,3.45178 5.82076,7.55014 6.70042,12.20905 1.37912,6.14476 1.64075,12.46375 1.94942,18.73243 0.44068,12.60915 0.36185,25.22847 0.46549,37.84313 0.12232,24.87841 0.24514,49.75683 0.3678,74.63524 17.27846,0.21456 34.55844,0.23924 51.83792,0.29199 1.06467,-1.5251 0.31735,-3.42695 0.43814,-5.1264 0.2161,-8.12865 0.0595,-16.26061 0.10191,-24.39093 -0.0169,-30.92436 -0.0238,-61.84874 -0.0357,-92.7731 -1.32357,-10.83941 -2.97316,-21.63894 -5.01024,-32.36767 -1.15062,-3.05918 -2.66056,-5.9687 -4.12768,-8.88497 -2.33847,-4.51988 -4.95571,-8.89474 -7.83067,-13.09385 -5.16042,-5.49834 -11.75416,-9.3415 -18.36215,-12.83427 -9.55618,-4.03007 -20.01615,-5.5409 -30.34022,-5.38521 z" />
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
