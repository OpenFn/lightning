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

  describe "header/1 breadcrumbs" do
    import Lightning.ProjectsFixtures

    test "renders regular project breadcrumb" do
      user = Lightning.AccountsFixtures.user_fixture()
      project = project_fixture()

      assigns = %{
        current_user: user,
        socket: nil,
        breadcrumbs: [],
        project: project,
        title: []
      }

      html =
        (&LayoutComponents.header/1)
        |> render_component(assigns)

      # Project name shown via project picker button (no "Projects" prefix)
      assert html =~ project.name
      assert html =~ "breadcrumb-project-picker-trigger"
      refute html =~ "parent"
    end

    test "renders sandbox breadcrumb with parent project" do
      user = Lightning.AccountsFixtures.user_fixture()
      parent_project = project_fixture(name: "Parent Project")

      sandbox_project =
        project_fixture(name: "My Sandbox", parent_id: parent_project.id)
        |> Lightning.Repo.preload(:parent)

      assigns = %{
        current_user: user,
        socket: nil,
        breadcrumbs: [],
        project: sandbox_project,
        title: []
      }

      html =
        (&LayoutComponents.header/1)
        |> render_component(assigns)

      # Current project shown in project picker button
      assert html =~ "My Sandbox"
      assert html =~ "breadcrumb-project-picker-trigger"
    end

    test "renders sandbox breadcrumb without parent when parent not preloaded" do
      user = Lightning.AccountsFixtures.user_fixture()
      parent_project = project_fixture(name: "Parent Project")

      sandbox_project =
        project_fixture(name: "My Sandbox", parent_id: parent_project.id)

      assigns = %{
        current_user: user,
        socket: nil,
        breadcrumbs: [],
        project: sandbox_project,
        title: []
      }

      html =
        (&LayoutComponents.header/1)
        |> render_component(assigns)

      # Current project shown in project picker button (parent not shown)
      refute html =~ "Parent Project"
      assert html =~ "My Sandbox"
      assert html =~ "breadcrumb-project-picker-trigger"
    end

    test "renders multiple breadcrumbs with separators" do
      user = Lightning.AccountsFixtures.user_fixture()
      project = project_fixture(name: "Test Project")

      # Note: collect_breadcrumbs/1 auto-adds project as first crumb,
      # so we add 2 more breadcrumbs to get 3 total (indices 0, 1, 2)
      # This ensures index > 1 is true for the third breadcrumb
      assigns = %{
        current_user: user,
        socket: nil,
        breadcrumbs: [
          {"Workflows", "/projects/#{project.id}/w"},
          {"My Workflow", "/projects/#{project.id}/w/abc"}
        ],
        project: project,
        title: []
      }

      html =
        (&LayoutComponents.header/1)
        |> render_component(assigns)

      # First breadcrumb (index 0) uses project picker
      assert html =~ "breadcrumb-project-picker-trigger"
      assert html =~ "Test Project"

      # Second breadcrumb (index 1) rendered via else branch
      # show_separator = (1 > 1) = false, so no separator before "Workflows"
      assert html =~ "Workflows"

      # Third breadcrumb (index 2) rendered via else branch
      # show_separator = (2 > 1) = true, so separator shown before "My Workflow"
      assert html =~ "My Workflow"

      # Verify separator icons are present (from index 2 and page title)
      assert html =~ "hero-chevron-right"
    end
  end
end
