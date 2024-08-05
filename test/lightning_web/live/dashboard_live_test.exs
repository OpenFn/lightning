defmodule LightningWeb.DashboardLiveTest do
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

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(2)",
                 role
                 |> Atom.to_string()
                 |> String.capitalize()
               )

        workflow_count =
          project
          |> Repo.preload(:workflows)
          |> Map.get(:workflows)
          |> Enum.count()

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(3)",
                 workflow_count |> to_string()
               )

        collaborator_count =
          project
          |> Repo.preload(:project_users)
          |> Map.get(:project_users)
          |> Enum.count()

        assert has_element?(
                 view,
                 "tr#projects-table-row-#{project.id} > td:nth-child(4) > a[href='/projects/#{project.id}/settings#collaboration']",
                 collaborator_count |> to_string()
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

    test "User can create a new project", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      projects_before = Lightning.Projects.get_projects_for_user(user)
      assert projects_before |> Enum.count() == 0

      view
      |> form("#project-form",
        project: %{
          raw_name: "My Awesome Project",
          description: "This is a really awesome project for testing purposes"
        }
      )
      |> render_change()

      assert view
             |> has_element?("input[type='hidden'][value='my-awesome-project']")

      view |> form("#project-form") |> render_submit()

      projects_after = Lightning.Projects.get_projects_for_user(user)
      assert projects_after |> Enum.count() == 1

      project = List.first(projects_after)

      {:ok, view, _html} = live(conn, ~p"/projects")

      assert has_element?(
               view,
               "tr#projects-table-row-#{project.id}"
             )
    end

    test "When the user closes the modal without submitting the form, the project won't be created",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      projects_before = Lightning.Projects.get_projects_for_user(user)
      assert projects_before |> Enum.count() == 0

      view
      |> form("#project-form",
        project: %{
          raw_name: "My Awesome Project",
          description: "This is a really awesome project for testing purposes"
        }
      )
      |> render_change()

      view |> element("#cancel-project-creation") |> render_click()

      projects_after = Lightning.Projects.get_projects_for_user(user)
      assert projects_after |> Enum.count() == 0
    end

    test "Users can sort the project table by name", %{conn: conn, user: user} do
      projects =
        insert_list(3, :project,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects")

      # By default, projects are sorted by name ascending
      projects_sorted_by_name = get_sorted_projects_by_name(projects)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)

      assert project_names_from_html == projects_sorted_by_name

      # Click to sort by name descending
      view |> element("span[phx-click='sort_by_name']") |> render_click()

      projects_sorted_by_name_desc = get_sorted_projects_by_name(projects, :desc)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)

      assert project_names_from_html == projects_sorted_by_name_desc
    end

    test "Users can sort the project table by last activity", %{
      conn: conn,
      user: user
    } do
      projects =
        insert_list(3, :project,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects")

      # By default, projects are sorted by last activity ascending
      projects_sorted_by_last_activity =
        get_sorted_projects_by_last_activity(projects)
        |> Enum.map(fn date ->
          Lightning.Helpers.format_date(
            date,
            "%d/%b/%Y %H:%M:%S"
          )
        end)

      html = render(view)

      project_last_activities_from_html =
        extract_project_last_activities_from_html(html)

      assert project_last_activities_from_html ==
               projects_sorted_by_last_activity

      # Click to sort by last activity descending
      view |> element("span[phx-click='sort_by_activity']") |> render_click()

      projects_sorted_by_last_activity_desc =
        get_sorted_projects_by_last_activity(projects, :desc)
        |> Enum.map(fn date ->
          Lightning.Helpers.format_date(
            date,
            "%d/%b/%Y %H:%M:%S"
          )
        end)

      html = render(view)

      project_last_activities_from_html =
        extract_project_last_activities_from_html(html)

      assert project_last_activities_from_html ==
               projects_sorted_by_last_activity_desc
    end
  end

  defp get_sorted_projects_by_name(projects, order \\ :asc) do
    projects
    |> Enum.sort_by(fn project -> project.name end, order)
    |> Enum.map(& &1.name)
  end

  defp get_sorted_projects_by_last_activity(projects, order \\ :asc) do
    projects
    |> Enum.sort_by(fn project -> project.updated_at end, order)
    |> Enum.map(& &1.updated_at)
  end

  defp extract_project_names_from_html(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#projects-table tr")
    |> Enum.map(fn tr ->
      Floki.find(tr, "td:nth-child(1) a")
      |> Floki.text()
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_project_last_activities_from_html(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#projects-table tr")
    |> Enum.map(fn tr ->
      Floki.find(tr, "td:nth-child(5)")
      |> Floki.text()
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end
end
