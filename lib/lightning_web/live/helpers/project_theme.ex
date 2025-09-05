defmodule LightningWeb.Live.Helpers.ProjectTheme do
  @moduledoc """
  Produces inline CSS variable styles for the left side menu, derived from a project's color.
  Used to tint the menu when the loaded project is a sandbox.
  """

  alias Lightning.Projects.Project

  @default nil

  @spec inline_style_for(Project.t() | nil) :: String.t() | nil
  def inline_style_for(%Project{} = project) do
    cond do
      not Project.sandbox?(project) ->
        @default

      is_nil(project.color) ->
        @default

      true ->
        hex = normalize_hex(project.color)

        bg = hex
        bg_light = lighten(hex, 0.12)
        bg_dark = darken(hex, 0.14)
        text = text_contrast(hex)
        text_lg = mix(text, "#ffffff", 0.35)
        text_lgr = mix(text, "#ffffff", 0.55)
        ring = "var(--color-gray-300)"
        ring_f = bg_light

        """
        --primary-bg: #{bg};
        --primary-text: #{text};
        --primary-bg-lighter: #{bg_light};
        --primary-bg-dark: #{bg_dark};
        --primary-text-light: #{text_lg};
        --primary-text-lighter: #{text_lgr};
        --primary-ring: #{ring};
        --primary-ring-focus: #{ring_f};
        """
        |> String.trim()
    end
  end

  def inline_style_for(_), do: @default

  defp normalize_hex(nil), do: "#6b7280"
  defp normalize_hex("#" <> _ = hex) when byte_size(hex) in [4, 7, 9], do: hex
  defp normalize_hex(hex), do: "#" <> hex

  defp lighten(hex, pct), do: adjust(hex, pct)
  defp darken(hex, pct), do: adjust(hex, -pct)

  defp adjust(hex, pct) do
    {r, g, b} = hex_to_rgb(hex)

    {r2, g2, b2} = {
      clamp(r + (255 - r) * pct),
      clamp(g + (255 - g) * pct),
      clamp(b + (255 - b) * pct)
    }

    rgb_to_hex({r2, g2, b2})
  end

  defp text_contrast(hex) do
    {r, g, b} = hex_to_rgb(hex)
    yiq = (r * 299 + g * 587 + b * 114) / 1000
    if yiq >= 150, do: "#111827", else: "#ffffff"
  end

  defp mix(hex_a, hex_b, pct) do
    {r1, g1, b1} = hex_to_rgb(hex_a)
    {r2, g2, b2} = hex_to_rgb(hex_b)
    r = clamp(r1 + pct * (r2 - r1))
    g = clamp(g1 + pct * (g2 - g1))
    b = clamp(b1 + pct * (b2 - b1))
    rgb_to_hex({r, g, b})
  end

  defp hex_to_rgb("#" <> hex) do
    case String.length(hex) do
      3 ->
        <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> = hex
        {dup(r), dup(g), dup(b)}

      6 ->
        <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex

        {String.to_integer(r, 16), String.to_integer(g, 16),
         String.to_integer(b, 16)}

      8 ->
        <<r::binary-size(2), g::binary-size(2), b::binary-size(2),
          _a::binary-size(2)>> = hex

        {String.to_integer(r, 16), String.to_integer(g, 16),
         String.to_integer(b, 16)}

      _ ->
        {107, 114, 128}
    end
  end

  defp rgb_to_hex({r, g, b}) do
    "#" <>
      for(
        c <- [r, g, b],
        into: "",
        do: c |> round() |> Integer.to_string(16) |> String.pad_leading(2, "0")
      )
  end

  defp dup(<<x>>) do
    v = String.to_integer(<<x, x>>, 16)
    v
  end

  defp clamp(v) when is_float(v), do: clamp(round(v))
  defp clamp(v) when v < 0, do: 0
  defp clamp(v) when v > 255, do: 255
  defp clamp(v), do: v
end
