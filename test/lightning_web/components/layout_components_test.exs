defmodule LightningWeb.LayoutComponentsTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.LayoutComponents

  test "menu_item/1 renders project menu item" do
    icon = &Heroicons.academic_cap/1

    on_exit(fn -> Application.delete_env(:lightning, :menu_items) end)

    Application.put_env(:lightning, :menu_items,
      project_menu: [
        {"/somepath1", icon, "CustomProjectMenu", :the_active_proj_menu}
      ]
    )

    assigns = %{
      active_menu_item: :the_active_proj_menu,
      project: %Lightning.Projects.Project{id: Ecto.UUID.generate()}
    }

    element =
      (&LayoutComponents.menu_items/1)
      |> render_component(assigns)
      |> Floki.find("a[href='/somepath1']")

    assert Floki.text(element) == "CustomProjectMenu"

    assert element_to_svg(element) == render_svg(icon)

    assert element |> Floki.attribute("class") |> hd =~
             "text-primary-200 bg-primary-900"
  end

  test "menu_item/1 renders menu items replacing them all" do
    icon1 = &Heroicons.archive_box/1
    icon2 = &Heroicons.arrow_down/1

    on_exit(fn -> Application.delete_env(:lightning, :menu_items) end)

    Application.put_env(:lightning, :menu_items,
      replace_projects_menu: [
        {"/replace-path1", icon1, "CustomMenu1", :menu1},
        {"/replace-path2", icon2, "CustomMenu2", :menu2}
      ]
    )

    assigns = %{
      active_menu_item: :menu2,
      projects: [%Lightning.Projects.Project{id: Ecto.UUID.generate()}]
    }

    menu_items =
      (&LayoutComponents.menu_items/1)
      |> render_component(assigns)

    element1 = menu_items |> Floki.find("a[href='/replace-path1']")
    element2 = menu_items |> Floki.find("a[href='/replace-path2']")

    assert Floki.text(element1) == "CustomMenu1"
    assert Floki.text(element2) == "CustomMenu2"

    assert element_to_svg(element1) == render_svg(icon1)
    assert element_to_svg(element2) == render_svg(icon2)

    refute element1 |> Floki.attribute("class") |> hd =~
             "text-primary-200 bg-primary-900"

    assert element2 |> Floki.attribute("class") |> hd =~
             "text-primary-200 bg-primary-900"
  end

  defp element_to_svg(element) do
    element
    |> Floki.find("svg")
    |> Floki.raw_html()
    |> String.replace("></path>", "/>\n")
    |> String.replace("viewbox", "viewBox")
  end

  defp render_svg(icon_fn) do
    icon_fn
    |> render_component(%{class: "h-5 w-5 inline-block mr-1"})
    |> String.replace("\n  <path", "<path")
  end
end
