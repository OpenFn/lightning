defmodule LightningWeb.Components.UI.Badge do
  @moduledoc false
  # A badge is a look, never a role. Labels render <.badge>, a span. Real
  # buttons and links that need the look keep their element and take
  # badge_class/1. Styled by .ui-badge in assets/css/ui/badge.css.
  use Phoenix.Component

  import LightningWeb.Components.Icons

  @colors %{
    "neutral" => "ui-badge--neutral",
    "success" => "ui-badge--success",
    "warning" => "ui-badge--warning",
    "danger" => "ui-badge--danger",
    "info" => "ui-badge--info",
    "brand" => "ui-badge--brand",
    "orange" => "ui-badge--orange",
    "dark" => "ui-badge--dark"
  }

  @doc """
  ## Examples

      <.badge>main</.badge>

      <.badge color="success" icon="hero-bolt">Webhook</.badge>

      <.badge id="env-badge-1" class="max-w-32">
        <span class="truncate">{@env}</span>
      </.badge>

      <.badge dot pulse={@running?} color="info">Running</.badge>

      <.badge color="brand">
        {project.name}
        <:remove
          label={"Remove \#{project.name}"}
          id={"remove-project-\#{project.id}"}
          phx-click="remove_selected_project"
          phx-value-project_id={project.id}
        />
      </.badge>
  """
  attr :color, :string, values: Map.keys(@colors), default: "neutral"
  attr :size, :string, values: ~w(default small), default: "default"
  attr :mono, :boolean, default: false
  attr :dot, :boolean, default: false
  attr :pulse, :boolean, default: false, doc: "Pings the dot. Needs `dot`."
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  # No declared attrs: in LiveView 1.0 declaring any would warn on the
  # pass-through ones. `label` is required and checked at render.
  slot :remove, validate_attrs: false

  def badge(assigns) do
    ~H"""
    <span class={badge_class(assigns)} {@rest}>
      <span :if={@dot} class="ui-badge__dot">
        <span :if={@pulse} class="ui-badge__pulse"></span>
      </span>
      <.icon :if={@icon} name={@icon} class="ui-badge__icon" />
      {render_slot(@inner_block)}
      <button
        :for={remove <- @remove}
        type="button"
        class="ui-badge__remove"
        aria-label={remove_label!(remove)}
        {assigns_to_attributes(remove, [:label])}
      >
        <.icon name="hero-x-mark-micro" class="h-3 w-3" />
      </button>
    </span>
    """
  end

  @doc """
  The badge class list, for real buttons and links that need the look. Takes
  the badge options plus `interactive`, which adds hover and focus styles.

      <button class={badge_class(color: "brand", interactive: true)}>...</button>
  """
  def badge_class(opts) do
    opts = Map.new(opts)

    [
      "ui-badge",
      Map.fetch!(@colors, Map.get(opts, :color) || "neutral"),
      Map.get(opts, :size) == "small" && "ui-badge--small",
      Map.get(opts, :mono) && "ui-badge--mono",
      Map.get(opts, :dot) && "ui-badge--dot",
      Map.get(opts, :interactive) && "ui-badge--interactive",
      Map.get(opts, :class)
    ]
    |> Enum.filter(& &1)
  end

  defp remove_label!(%{label: label}) when is_binary(label), do: label

  defp remove_label!(_entry),
    do: raise(ArgumentError, "the :remove slot of badge/1 needs a label")
end
