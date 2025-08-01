defmodule LightningWeb.Components.MenuTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.LayoutComponents

  describe "menu_items/1" do
    test "renders project menu items when project is present" do
      project_id = Ecto.UUID.generate()

      assigns = %{
        active_menu_item: :settings,
        project: %{id: project_id, name: "project-1"},
        projects: []
      }

      element =
        (&LayoutComponents.menu_items/1)
        |> render_component(assigns)
        |> find_by_href("/projects/#{project_id}/w")

      assert Floki.text(element) == "Workflows"

      assert element |> Floki.attribute("class") |> hd =~
               "menu-item-inactive"
    end
  end

  describe "project_items/1" do
    test "renders menu items from project scope" do
      project_id = Ecto.UUID.generate()

      menu =
        render_component(
          &LayoutComponents.menu_items/1,
          %{
            active_menu_item: :settings,
            project: %{id: project_id, name: "project-1"},
            projects: []
          }
        )

      element = find_by_href(menu, "/projects/#{project_id}/w")

      assert Floki.text(element) == "Workflows"

      assert element |> Floki.attribute("class") |> hd =~
               "menu-item-inactive"

      element = find_by_href(menu, "/projects/#{project_id}/history")

      assert Floki.text(element) == "History"

      assert element |> Floki.attribute("class") |> hd =~
               "menu-item-inactive"

      element = find_by_href(menu, "/projects/#{project_id}/settings")

      assert Floki.text(element) == "Settings"

      assert element |> Floki.attribute("class") |> hd =~
               "menu-item-active"
    end
  end

  describe "profile_items/1" do
    test "renders menu items from user/profile scope" do
      menu =
        render_component(
          &LayoutComponents.menu_items/1,
          %{
            active_menu_item: :credentials
          }
        )

      element = find_by_href(menu, "/profile")

      assert Floki.text(element) =~ "User Profile"

      assert element |> Floki.attribute("class") |> hd =~
               "menu-item-inactive"

      element = find_by_href(menu, "/credentials")

      assert Floki.text(element) =~ "Credentials"

      assert element |> Floki.attribute("class") |> hd =~
               "menu-item-active"

      element =
        find_by_href(menu, "/profile/tokens")

      assert Floki.text(element) =~ "API Tokens"

      assert element |> Floki.attribute("class") |> hd =~
               "menu-item-inactive"
    end
  end

  defp find_by_href(html, href) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("a[href='#{href}']")
  end
end
