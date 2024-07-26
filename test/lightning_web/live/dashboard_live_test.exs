defmodule LightningWeb.DashboardLiveTest do
  alias Lightning.Projects.Project
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  describe "Index" do
    setup :register_and_log_in_user

    test "User is assigned no project", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/projects")

      assert html =~ "No projects found. Create a new one."

      assert html =~ "User Profile"
      assert html =~ "Credentials"
    end

    test "Side menu has credentials and user profile navigation", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/projects")

      assert index_live
             |> has_element?("nav#side-menu a[href='/projects']", "Projects")

      assert index_live
             |> has_element?("nav#side-menu a[href='/profile']", "User Profile")

      assert index_live
             |> has_element?(
               "nav#side-menu a[href='/credentials']",
               "Credentials"
             )

      assert index_live
             |> has_element?(
               "nav#side-menu a[href='/profile/tokens']",
               "API Tokens"
             )

      assert {:ok, profile_live, _html} =
               index_live
               |> element("nav#side-menu a", "User Profile")
               |> render_click()
               |> follow_redirect(conn, ~p"/profile")

      assert profile_live
             |> element("nav#side-menu a", "Credentials")
             |> render_click()
             |> follow_redirect(conn, ~p"/credentials")
    end

    test "User's projects are listed", %{conn: conn, user: user} do
      project_1 = insert(:project, project_users: [%{user: user, role: :owner}])

      project_2 =
        insert(:project,
          project_users: [
            %{user: user, role: :admin},
            %{user: build(:user), role: :owner}
          ]
        )

      project_3 =
        insert(:project, project_users: [%{user: build(:user), role: :owner}])

      insert_list(2, :simple_workflow, project: project_1)

      {:ok, view, _html} = live(conn, ~p"/projects")

      refute has_element?(view, "#projects-table-row-#{project_3.id}")

      [project_1, project_2]
      |> Enum.each(fn project ->
        assert has_element?(view, "tr#projects-table-row-#{project.id}")

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(1) > a[href='/projects/#{project.id}/w']",
                 project.name
               )

        role =
          project
          |> Repo.preload(:project_users)
          |> Map.get(:project_users)
          |> Enum.find(fn pu -> pu.user_id == user.id end)
          |> Map.get(:role)
          |> Atom.to_string()
          |> String.capitalize()

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(2)",
                 role
               )

        workflow_count =
          project
          |> Repo.preload(:workflows)
          |> Map.get(:workflows)
          |> Enum.count()
          |> to_string()

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(3)",
                 workflow_count
               )

        collaborator_count =
          project
          |> Repo.preload(:project_users)
          |> Map.get(:project_users)
          |> Enum.count()
          |> to_string()

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(4) > a[href='/projects/#{project.id}/settings#collaboration']",
                 collaborator_count
               )

        formatted_date =
          Lightning.Helpers.format_date(project.updated_at, "%d/%b/%Y %H:%M:%S")

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(5)",
                 formatted_date
               )
      end)
    end

    test "User can create a new project", %{conn: conn, user: _user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      Repo.all(Project) |> IO.inspect()

      # assert
      view
      |> form("#project-form",
        project: %{
          raw_name: "My Awesome Project",
          description: "This is a really awesome project for testing purposes"
        }
      )
      |> render_change()
      |> IO.puts()

      # |> follow_redirect(conn, ~p"/")

      # |> IO.puts() =~ "Project created successfully"

      view |> form("#project-form") |> render_submit()

      Repo.all(Project) |> IO.inspect()
    end
  end
end
