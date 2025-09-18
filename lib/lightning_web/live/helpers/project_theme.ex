defmodule LightningWeb.Live.Helpers.ProjectTheme do
  @moduledoc """
  Runtime theme utilities. Builds a full primary scale (50..950) from a base hex
  and returns inline CSS variable overrides for Tailwind v4's `--color-primary-*`.
  """

  alias Lightning.Projects.Project

  @stops [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
  @openfn_blue "#6366f1"

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
        scale = build_scale(p.color)

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
    %{h: h, s: s, l: _l} = Chameleon.convert(hex, Chameleon.HSL)
    build_scale_with_hsl(h, s)
  rescue
    _ -> build_default_scale()
  end

  defp build_default_scale do
    %{h: h, s: s, l: _l} = Chameleon.convert(@openfn_blue, Chameleon.HSL)
    build_scale_with_hsl(h, s)
  end

  defp build_scale_with_hsl(h, s) do
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

    Enum.reduce(targets, %{}, fn {stop, target_lightness}, acc ->
      adjusted_saturation =
        cond do
          target_lightness >= 0.9 -> s * 0.75
          target_lightness >= 0.7 -> s * 0.9
          target_lightness >= 0.5 -> s
          true -> min(100, s * 1.05)
        end

      color =
        %Chameleon.HSL{h: h, s: adjusted_saturation, l: target_lightness * 100}
        |> Chameleon.convert(Chameleon.Hex)

      Map.put(acc, stop, "##{color.hex}")
    end)
  end
end
