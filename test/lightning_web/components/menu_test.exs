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
        project: %{id: project_id}
      }

      element =
        (&LayoutComponents.menu_items/1)
        |> render_component(assigns)
        |> Floki.find("a[href='/projects/#{project_id}/w']")

      assert Floki.text(element) == "Workflows"

      assert element |> Floki.attribute("class") |> hd =~
               "text-primary-300 hover:bg-primary-900"
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
            project: %{id: project_id}
          }
        )

      element = Floki.find(menu, "a[href='/projects/#{project_id}/w']")

      assert Floki.text(element) == "Workflows"

      assert element |> Floki.attribute("class") |> hd =~
               "text-primary-300 hover:bg-primary-900"

      element = Floki.find(menu, "a[href='/projects/#{project_id}/history']")

      assert Floki.text(element) == "History"

      assert element |> Floki.attribute("class") |> hd =~
               "text-primary-300 hover:bg-primary-900"

      element = Floki.find(menu, "a[href='/projects/#{project_id}/settings']")

      assert Floki.text(element) == "Settings"

      assert element |> Floki.attribute("class") |> hd =~
               "text-primary-200 bg-primary-900"
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

      element = Floki.find(menu, "a[href='/profile']")

      assert Floki.text(element) =~ "User Profile"

      assert element |> Floki.attribute("class") |> hd =~
               "text-primary-300 hover:bg-primary-900"

      element = Floki.find(menu, "a[href='/credentials']")

      assert Floki.text(element) =~ "Credentials"

      assert element |> Floki.attribute("class") |> hd =~
               "text-primary-200 bg-primary-900"

      element =
        Floki.find(menu, "a[href='/profile/tokens']")

      assert Floki.text(element) =~ "API Tokens"

      assert element |> Floki.attribute("class") |> hd =~
               "text-primary-300 hover:bg-primary-900"
    end
  end
end
