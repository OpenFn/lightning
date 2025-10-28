defmodule LightningWeb.LayoutComponentsTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.LayoutComponents
  alias LightningWeb.Components.Menu

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

      assert html =~ "Projects"
      assert html =~ project.name
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

      assert html =~ "Projects"
      assert html =~ "Parent Project"
      assert html =~ "My Sandbox"

      parsed = Floki.parse_fragment!(html)
      breadcrumb_links = Floki.find(parsed, "nav ol li a")

      breadcrumb_texts =
        breadcrumb_links
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)

      assert "Parent Project" in breadcrumb_texts
      assert "My Sandbox" in breadcrumb_texts

      breadcrumb_index_parent =
        Enum.find_index(breadcrumb_texts, &(&1 == "Parent Project"))

      breadcrumb_index_sandbox =
        Enum.find_index(breadcrumb_texts, &(&1 == "My Sandbox"))

      assert breadcrumb_index_parent < breadcrumb_index_sandbox
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

      assert html =~ "Projects"
      refute html =~ "Parent Project"
      assert html =~ "My Sandbox"
    end
  end
end
