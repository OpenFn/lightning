defmodule LightningWeb.LayoutComponentsTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest
  import Lightning.Factories

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
    test "renders the ReactComponent mount point for a root project" do
      project = %Lightning.Projects.Project{
        id: Ecto.UUID.generate(),
        name: "my-project",
        parent_id: nil
      }

      html =
        (&LayoutComponents.breadcrumb_project_picker/1)
        |> render_component(%{project: project, label: "my-project"})

      assert html =~ "breadcrumb-project-picker-trigger"
      assert html =~ ~s(data-react-name="PickerButton")
      assert html =~ ~s(data-label="my-project")
      assert html =~ ~s(data-is-sandbox="false")
    end

    test "renders the ReactComponent mount point for a sandbox" do
      parent = %Lightning.Projects.Project{
        id: Ecto.UUID.generate(),
        name: "parent-project"
      }

      project = %Lightning.Projects.Project{
        id: Ecto.UUID.generate(),
        name: "my-sandbox",
        parent_id: parent.id,
        parent: parent,
        color: "#E33D63"
      }

      html =
        (&LayoutComponents.breadcrumb_project_picker/1)
        |> render_component(%{
          project: project,
          label: "parent-project/my-sandbox"
        })

      assert html =~ "breadcrumb-project-picker-trigger"
      assert html =~ ~s(data-react-name="PickerButton")
      assert html =~ ~s(data-label="parent-project/my-sandbox")
      assert html =~ ~s(data-is-sandbox="true")
      assert html =~ ~s(data-color="#E33D63")
    end
  end

  describe "global_project_picker/1" do
    test "renders nothing when no current_user" do
      html =
        (&LayoutComponents.global_project_picker/1)
        |> render_component(%{})

      refute html =~ "global-project-picker"
    end

    test "items nest a visible sandbox under its nearest visible ancestor when intermediates are hidden" do
      user = insert(:user)

      root =
        insert(:project,
          name: "root",
          project_users: [%{user: user, role: :editor}]
        )

      hidden_middle =
        insert(:project, name: "hidden-middle", parent: root)

      nested_member =
        insert(:project,
          name: "nested-member",
          parent: hidden_middle,
          project_users: [%{user: user, role: :viewer}]
        )

      html =
        (&LayoutComponents.global_project_picker/1)
        |> render_component(%{current_user: user, current_path: "/projects"})

      items =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("#global-project-picker")
        |> Floki.attribute("data-items")
        |> List.first()
        |> Jason.decode!()

      ids = Enum.map(items, & &1["id"])
      depth_by_id = Map.new(items, &{&1["id"], &1["depth"]})

      assert root.id in ids
      assert nested_member.id in ids
      refute hidden_middle.id in ids

      assert depth_by_id[root.id] == 0
      assert depth_by_id[nested_member.id] == 1
    end

    test "items surface a sandbox the user is a direct member of when the user has no role on its root" do
      user = insert(:user)
      absolute_root = insert(:project)

      sandbox =
        insert(:project,
          parent: absolute_root,
          project_users: [%{user: user, role: :owner}]
        )

      html =
        (&LayoutComponents.global_project_picker/1)
        |> render_component(%{current_user: user, current_path: "/projects"})

      items =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("#global-project-picker")
        |> Floki.attribute("data-items")
        |> List.first()
        |> Jason.decode!()

      ids = Enum.map(items, & &1["id"])
      depth_by_id = Map.new(items, &{&1["id"], &1["depth"]})

      assert ids == [sandbox.id]
      assert depth_by_id[sandbox.id] == 0
    end

    test "items omit sandboxes the user has no access to" do
      user = insert(:user)

      parent =
        insert(:project, project_users: [%{user: user, role: :editor}])

      visible_sandbox =
        insert(:project,
          parent: parent,
          project_users: [%{user: user, role: :viewer}]
        )

      hidden_sandbox = insert(:project, parent: parent)

      html =
        (&LayoutComponents.global_project_picker/1)
        |> render_component(%{current_user: user, current_path: "/projects"})

      items =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("#global-project-picker")
        |> Floki.attribute("data-items")
        |> List.first()
        |> Jason.decode!()

      ids = Enum.map(items, & &1["id"])

      assert parent.id in ids
      assert visible_sandbox.id in ids
      refute hidden_sandbox.id in ids
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

  describe "settings_menu_items_extension/1" do
    test "renders nothing when no extension is configured" do
      Application.delete_env(:lightning, :settings_menu_items_extension)

      html =
        (&LayoutComponents.settings_menu_items_extension/1)
        |> render_component(%{
          current_user: %Lightning.Accounts.User{},
          active_menu_item: :projects
        })

      assert html |> String.trim() == ""
    end

    test "renders the configured extension component with whitelisted assigns" do
      on_exit(fn ->
        Application.delete_env(:lightning, :settings_menu_items_extension)
      end)

      Application.put_env(:lightning, :settings_menu_items_extension, %{
        component: &Menu.profile_items/1,
        assigns_keys: [:active_menu_item]
      })

      html =
        (&LayoutComponents.settings_menu_items_extension/1)
        |> render_component(%{
          current_user: %Lightning.Accounts.User{},
          active_menu_item: :credentials
        })

      element =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("a[href='/credentials']")

      assert Floki.text(element) == "Credentials"

      assert element |> Floki.attribute("class") |> List.first() =~
               "menu-item-active"
    end
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
