defmodule LightningWeb.Live.Helpers.ProjectTheme do
  @moduledoc """
  Runtime theme utilities. Builds a full primary scale (50..950) from a base hex
  and returns inline CSS variable overrides for Tailwind v4's `--color-primary-*`.
  """

  alias Lightning.Projects.Project
  @stops [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

  @doc """
  If the project is a sandbox with a color, returns a string of CSS custom
  properties that override the full `--color-primary-*` scale.
  Returns `nil` for non-sandboxes or missing color.
  """
  @spec inline_primary_scale(Project.t() | nil) :: String.t() | nil
  def inline_primary_scale(%Project{} = p) do
    cond do
      not Project.sandbox?(p) ->
        nil

      is_nil(p.color) or String.trim(to_string(p.color)) == "" ->
        nil

      true ->
        hex = normalize_hex(p.color)
        scale = build_scale(hex)

        @stops
        |> Enum.map_join(" ", fn stop ->
          "--color-primary-#{stop}: #{Map.fetch!(scale, stop)};"
        end)
    end
  end

  def inline_primary_scale(_), do: nil

  @doc """
  Returns the sidebar variables that your CSS reads (`--primary-*`), pointing at the
  primary scale. Safe to append anywhere you put `inline_primary_scale/1`.
  """
  @spec inline_sidebar_vars() :: String.t()
  def inline_sidebar_vars do
    """
    --primary-bg: var(--color-primary-800);
    --primary-text: white;
    --primary-bg-lighter: var(--color-primary-600);
    --primary-bg-dark: var(--color-primary-900);
    --primary-text-light: var(--color-primary-300);
    --primary-text-lighter: var(--color-primary-200);
    --primary-ring: var(--color-gray-300);
    --primary-ring-focus: var(--color-primary-600);
    """
    |> String.replace("\n", " ")
  end

  defp build_scale(hex) do
    {h, s, _l} = to_hsl(hex)

    targets = %{
      50 => 0.98,
      100 => 0.95,
      200 => 0.90,
      300 => 0.82,
      400 => 0.70,
      500 => 0.60,
      600 => 0.50,
      700 => 0.42,
      800 => 0.35,
      900 => 0.28,
      950 => 0.20
    }

    Enum.reduce(targets, %{}, fn {stop, lt}, acc ->
      s_adj =
        cond do
          lt >= 0.9 -> s * 0.75
          lt >= 0.7 -> s * 0.9
          lt >= 0.5 -> s
          true -> min(1.0, s * 1.05)
        end

      Map.put(acc, stop, from_hsl(h, s_adj, lt))
    end)
  end

  defp normalize_hex("#" <> _ = hex), do: hex
  defp normalize_hex(hex), do: "#" <> hex

  defp to_hsl(hex) do
    {r, g, b} = hex_to_rgb(hex)
    {h, s, l} = rgb_to_hsl(r / 255, g / 255, b / 255)
    {h, s, l}
  end

  defp from_hsl(h, s, l) do
    {r, g, b} = hsl_to_rgb(h, s, l)
    rgb_to_hex({round(r * 255), round(g * 255), round(b * 255)})
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
        {99, 102, 241}
    end
  end

  defp rgb_to_hex({r, g, b}),
    do:
      "#" <>
        for(
          c <- [r, g, b],
          into: "",
          do: Integer.to_string(c, 16) |> String.pad_leading(2, "0")
        )

  defp dup(<<x>>), do: String.to_integer(<<x, x>>, 16)

  defp rgb_to_hsl(r, g, b) do
    max = max(r, max(g, b))
    min = min(r, min(g, b))
    l = (max + min) / 2
    d = max - min

    {h, s} =
      if d == 0 do
        {0.0, 0.0}
      else
        s = d / (1 - abs(2 * l - 1))

        h =
          cond do
            max == r -> 60 * remf((g - b) / d, 6.0)
            max == g -> 60 * ((b - r) / d + 2)
            true -> 60 * ((r - g) / d + 4)
          end

        {h, s}
      end

    {remf(h, 360.0), s, l}
  end

  defp hsl_to_rgb(h, s, l) do
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs(remf(h / 60, 2.0) - 1))
    m = l - c / 2

    {r1, g1, b1} =
      cond do
        h < 60 -> {c, x, 0}
        h < 120 -> {x, c, 0}
        h < 180 -> {0, c, x}
        h < 240 -> {0, x, c}
        h < 300 -> {x, 0, c}
        true -> {c, 0, x}
      end

    {r1 + m, g1 + m, b1 + m}
  end

  defp remf(a, b), do: a - b * Float.floor(a / b)
end
