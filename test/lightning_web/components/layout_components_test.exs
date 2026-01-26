defmodule LightningWeb.LayoutComponentsTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.LayoutComponents
  alias LightningWeb.Components.Menu

  describe "user_avatar/1" do
    test "renders initials from first and last name" do
      html =
        (&LayoutComponents.user_avatar/1)
        |> render_component(%{first_name: "John", last_name: "Doe"})

      assert html =~ "JD"
    end

    test "renders initial from first name only when no last name" do
      html =
        (&LayoutComponents.user_avatar/1)
        |> render_component(%{first_name: "John", last_name: nil})

      # Only first initial when no last name
      refute html =~ "JD"
      assert html =~ "J\n"
    end

    test "applies custom class" do
      html =
        (&LayoutComponents.user_avatar/1)
        |> render_component(%{
          first_name: "John",
          last_name: nil,
          class: "custom-class"
        })

      assert html =~ "custom-class"
    end
  end

  describe "sidebar_footer/1" do
    test "renders sidebar footer with branding and toggle button" do
      html =
        (&LayoutComponents.sidebar_footer/1)
        |> render_component(%{})

      # Check for branding elements
      assert html =~ "sidebar-footer"
      assert html =~ "sidebar-branding-expanded"
      assert html =~ "sidebar-branding-collapsed"

      # Check for toggle button
      assert html =~ "toggle_sidebar"
      assert html =~ "sidebar-collapse-icon"
      assert html =~ "sidebar-expand-icon"

      # Check for version
      assert html =~ "v#{Application.spec(:lightning, :vsn)}"
    end
  end

  describe "breadcrumb_project_picker/1" do
    test "renders project picker button with label" do
      html =
        (&LayoutComponents.breadcrumb_project_picker/1)
        |> render_component(%{label: "My Project", show_separator: false})

      assert html =~ "breadcrumb-project-picker-trigger"
      assert html =~ "My Project"
      assert html =~ "open-project-picker"
    end
  end

  test "menu_item/1 renders custom menu items" do
    on_exit(fn -> Application.delete_env(:lightning, :menu_items) end)

    Application.put_env(:lightning, :menu_items, %{
      component: &Menu.project_items/1,
      assigns_keys: [:project_id, :active_menu_item, :current_user]
    })

    project_id = Ecto.UUID.generate()

    assigns = %{
      active_menu_item: :settings,
      project_id: project_id,
      current_user: %Lightning.Accounts.User{}
    }

    element =
      (&LayoutComponents.menu_items/1)
      |> render_component(assigns)
      |> Floki.parse_fragment!()
      |> Floki.find("a[href='/projects/#{project_id}/settings']")

    assert Floki.text(element) == "Settings"

    assert element |> Floki.attribute("class") |> List.first() =~
             "menu-item-active"
  end

  describe "breadcrumb_items/1" do
    test "renders breadcrumbs from list of tuples" do
      assigns = %{
        items: [
          {"History", "/projects/123/history"},
          {"Workflow", "/projects/123/w/abc"}
        ]
      }

      html =
        (&LayoutComponents.breadcrumb_items/1)
        |> render_component(assigns)

      assert html =~ "History"
      assert html =~ "/projects/123/history"
      assert html =~ "Workflow"
      assert html =~ "/projects/123/w/abc"
      assert html =~ "hero-chevron-right"
    end
  end

  describe "header/1" do
    test "renders h1 title when no breadcrumbs slot provided" do
      user = Lightning.AccountsFixtures.user_fixture()

      # When breadcrumbs slot is empty, header renders the title slot as h1
      assigns = %{
        current_user: user,
        socket: nil,
        breadcrumbs: [],
        title: [],
        inner_block: []
      }

      html =
        (&LayoutComponents.header/1)
        |> render_component(assigns)

      # Should render h1 for title
      assert html =~ ~r/<h1/
      assert html =~ "top-bar"
    end
  end
end
