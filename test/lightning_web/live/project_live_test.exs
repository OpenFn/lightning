defmodule LightningWeb.ProjectLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  @create_attrs %{
    raw_name: "some name"
  }
  @invalid_attrs %{raw_name: nil}

  defp create_project(_) do
    project = project_fixture()
    %{project: project}
  end

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the users page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))
        |> follow_redirect(conn, "/")

      assert html =~ "You can&#39;t access that page"
    end
  end

  describe "Index" do
    setup [:register_and_log_in_superuser, :create_project]

    test "lists all projects", %{conn: conn, project: project} do
      {:ok, _index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"
      assert html =~ project.name
    end

    test "saves new project", %{conn: conn} do
      user = user_fixture()

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert index_live |> element("a", "New Project") |> render_click() =~
               "Projects"

      assert_patch(index_live, Routes.project_index_path(conn, :new))

      assert index_live
             |> form("#project-form", project: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      index_live
      |> form("#project-form", project: @create_attrs)
      |> render_change()

      index_live
      |> element("#member_list")
      |> render_hook("select_item", %{"id" => user.id})

      index_live
      |> element("button", "Add")
      |> render_click()

      index_live
      |> form("#project-form")
      |> render_submit()

      assert_patch(index_live, Routes.project_index_path(conn, :index))
      assert render(index_live) =~ "Project created successfully"
    end
  end

  describe "projects picker dropdown" do
    setup :register_and_log_in_user

    test "lists all projects", %{conn: conn, user: user} do
      another_user = user_fixture()

      {:ok, project_1} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id}]
        })

      {:ok, project_2} =
        Lightning.Projects.create_project(%{
          name: "project-2",
          project_users: [%{user_id: user.id}]
        })

      {:ok, project_3} =
        Lightning.Projects.create_project(%{
          name: "project-3",
          project_users: [%{user_id: another_user.id}]
        })

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_dashboard_index_path(
            conn,
            :show,
            Lightning.Projects.first_project_for_user(user)
          )
        )

      assert view
             |> element(
               "a[href='#{Routes.project_dashboard_index_path(conn, :show, project_1.id)}']"
             )
             |> has_element?()

      assert view
             |> element(
               "a[href='#{Routes.project_dashboard_index_path(conn, :show, project_2.id)}']"
             )
             |> has_element?()

      refute view
             |> element(
               "a[href='#{Routes.project_dashboard_index_path(conn, :show, project_3.id)}']"
             )
             |> has_element?()

      {:ok, view, html} =
        live(
          conn,
          Routes.project_dashboard_index_path(conn, :show, project_1.id)
        )

      assert html =~ project_1.name
      assert view |> element("button", "#{project_1.name}") |> has_element?()

      assert view
             |> element(
               "a[href='#{Routes.project_dashboard_index_path(conn, :show, project_2.id)}']"
             )
             |> has_element?()

      refute view
             |> element(
               "a[href='#{Routes.project_dashboard_index_path(conn, :show, project_3.id)}']"
             )
             |> has_element?()

      {:ok, view, html} =
        live(
          conn,
          Routes.project_dashboard_index_path(conn, :show, project_2.id)
        )

      assert html =~ project_2.name
      assert view |> element("button", "#{project_2.name}") |> has_element?()

      assert view
             |> element(
               "a[href='#{Routes.project_dashboard_index_path(conn, :show, project_1.id)}']"
             )
             |> has_element?()

      refute view
             |> element(
               "a[href='#{Routes.project_dashboard_index_path(conn, :show, project_3.id)}']"
             )
             |> has_element?()

      assert live(
               conn,
               Routes.project_dashboard_index_path(conn, :show, project_3.id)
             ) ==
               {:error, {:redirect, %{flash: %{"nav" => :no_access}, to: "/"}}}
    end
  end
end
