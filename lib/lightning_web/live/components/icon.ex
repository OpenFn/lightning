defmodule LightningWeb.Components.Icon do
  @moduledoc """
  SVG Icons
  """
  use LightningWeb, :component

  def cog(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <circle cx="12" cy="12" r="3"></circle>
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z">
      </path>
    </.outer_svg>
    """
  end

  def logout(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
      />
    </.outer_svg>
    """
  end

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

  def archive(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"
      />
    </.outer_svg>
    """
  end

  def warning(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
      />
    </.outer_svg>
    """
  end

  defp outer_svg(assigns) do
    default_classes = ~w[h-5 w-5 inline-block]
    attrs = build_attrs(assigns, default_classes)

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
      {attrs}
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
