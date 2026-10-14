defmodule LightningWeb.Components.UI.Avatar do
  @moduledoc false
  # Styled by .ui-avatar in assets/css/ui/avatar.css, the same classes
  # assets/js/ui/Avatar.tsx uses.
  use Phoenix.Component

  import LightningWeb.Components.Icons

  @doc """
  Shows initials from the name, or the icon when there's no name. An image
  covers both, and removes itself if it fails to load so they show through.

  Hidden from screen readers unless it has a label, since a name usually sits
  beside it. With a label it reads as one image with that name.

  ## Examples

      <.avatar first_name="John" last_name="Doe" size="small" />
      <.avatar src={@picture} size="large" />
      <.avatar first_name="John" last_name="Doe" label="John Doe (john@example.com)" />
  """
  attr :first_name, :string, default: nil
  attr :last_name, :string, default: nil
  attr :src, :string, default: nil
  attr :label, :string, default: nil
  attr :icon, :string, default: "hero-user"
  attr :size, :string, values: ~w(small medium large), default: "medium"
  attr :class, :any, default: nil

  def avatar(assigns) do
    assigns =
      assign(assigns, :initials, initials(assigns.first_name, assigns.last_name))

    ~H"""
    <span
      class={[
        "ui-avatar",
        @size == "small" && "ui-avatar--small",
        @size == "large" && "ui-avatar--large",
        @class
      ]}
      role={@label && "img"}
      aria-label={@label}
      aria-hidden={!@label && "true"}
    >
      {@initials}
      <.icon :if={@initials == ""} name={@icon} class="ui-avatar__icon" />
      <img
        :if={@src}
        src={@src}
        alt=""
        class="ui-avatar__image"
        onerror="this.remove()"
      />
    </span>
    """
  end

  defp initials(first_name, last_name) do
    for name <- [first_name, last_name],
        name = String.trim(name || ""),
        name != "",
        into: "",
        do: String.upcase(String.first(name))
  end
end
