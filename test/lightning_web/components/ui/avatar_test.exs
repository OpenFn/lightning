defmodule LightningWeb.Components.UI.AvatarTest do
  @moduledoc false
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.UI.Avatar

  defp render_avatar(assigns) do
    render_component(&Avatar.avatar/1, assigns) |> Floki.parse_fragment!()
  end

  defp text(html), do: html |> Floki.text() |> String.trim()

  test "shows upcased initials from first and last name" do
    html = render_avatar(%{first_name: "ada", last_name: "lovelace"})

    assert text(html) == "AL"
    assert Floki.find(html, ".ui-avatar__icon") == []
  end

  test "shows one initial when there's only one name" do
    assert text(render_avatar(%{first_name: "Ada"})) == "A"
    assert text(render_avatar(%{first_name: " ", last_name: "Lovelace"})) == "L"
  end

  test "shows the icon when there's no name" do
    assert [_] = Floki.find(render_avatar(%{}), ".ui-avatar__icon.hero-user")

    assert [_] =
             Floki.find(
               render_avatar(%{icon: "hero-rocket-launch"}),
               ".ui-avatar__icon.hero-rocket-launch"
             )
  end

  test "puts the image over the initials, which stay as the fallback" do
    html = render_avatar(%{first_name: "Ada", src: "/a.png"})

    assert text(html) == "A"

    assert [img] = Floki.find(html, "img.ui-avatar__image")
    assert Floki.attribute(img, "src") == ["/a.png"]
    assert Floki.attribute(img, "alt") == [""]
    assert Floki.attribute(img, "onerror") == ["this.remove()"]
  end

  test "is hidden from screen readers unless it has a label" do
    [avatar] = render_avatar(%{first_name: "Ada"})
    assert Floki.attribute(avatar, "aria-hidden") == ["true"]
    assert Floki.attribute(avatar, "role") == []

    [avatar] = render_avatar(%{first_name: "Ada", label: "Ada Lovelace"})
    assert Floki.attribute(avatar, "aria-hidden") == []
    assert Floki.attribute(avatar, "role") == ["img"]
    assert Floki.attribute(avatar, "aria-label") == ["Ada Lovelace"]
  end

  test "maps size to a modifier class and keeps the caller's class" do
    classes = fn assigns ->
      render_avatar(assigns)
      |> Floki.attribute("class")
      |> Enum.flat_map(&String.split/1)
    end

    assert classes.(%{}) == ["ui-avatar"]

    assert classes.(%{size: "small", class: "x"}) ==
             ["ui-avatar", "ui-avatar--small", "x"]

    assert classes.(%{size: "large"}) == ["ui-avatar", "ui-avatar--large"]
  end
end
