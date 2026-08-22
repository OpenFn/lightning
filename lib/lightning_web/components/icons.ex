defmodule LightningWeb.Components.Icons do
  @moduledoc false

  use Phoenix.Component

  @doc """
  Renders a [Heroicon](https://heroicons.com) or [Lucide](https://lucide.dev) icon.

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  Lucide icons use the `lucide-` prefix (e.g. `lucide-square-arrow-right`).

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/` directory and bundled
  within your compiled app.css by the plugins in your `assets/tailwind.config.ts`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-play-circle" class="ml-1 w-3 h-3 animate-spin" />
      <.icon name="lucide-square-arrow-right" class="h-4 w-4" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :naked, :boolean, default: false
  attr :rest, :global

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span
      class={[
        @naked && "text-gray-500 hover:text-primary-400",
        @name,
        @class
      ]}
      {@rest}
    />
    """
  end

  def icon(%{name: "lucide-" <> _} = assigns) do
    ~H"""
    <span
      class={[
        @naked && "text-gray-500 hover:text-primary-400",
        @name,
        @class
      ]}
      {@rest}
    />
    """
  end
end
