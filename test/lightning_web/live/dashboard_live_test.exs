defmodule LightningWeb.DashboardLiveTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Workflows.Workflow

  require Ecto.Query

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

      workflow_1 = insert(:simple_workflow, project: project_1)

      insert(:simple_workflow, project: project_2)

      insert(:workorder,
        workflow: workflow_1,
        last_activity: ~U[2023-10-05 00:00:00Z]
      )

      insert(:workorder,
        workflow: workflow_1,
        last_activity: ~U[2023-10-10 00:00:00Z]
      )

      {:ok, view, _html} = live(conn, ~p"/projects")

      refute has_element?(view, "#projects-table-row-#{project_3.id}")

      assert_project_listed(view, project_1, user, ~N[2023-10-10 00:00:00])
      assert_project_listed(view, project_2, user, nil)
    end

    test "projects list do not count deleted workflows", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      insert_list(2, :simple_workflow, project: project)
      insert(:workflow, deleted_at: Timex.now(), project: project)

      workflows_count =
        from(w in Workflow,
          where: w.project_id == ^project.id,
          where: is_nil(w.deleted_at),
          select: count(w.id)
        )
        |> Repo.one()

      {:ok, view, _html} = live(conn, ~p"/projects")

      assert has_element?(view, "tr#projects-table-row-#{project.id}")

      assert has_element?(
               view,
               "tr#projects-table-row-#{project.id} > td:nth-child(3)",
               "#{workflows_count}"
             )
    end

    test "User can create a new project", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      assert Enum.empty?(Lightning.Projects.get_projects_for_user(user))

      view
      |> form("#project-form",
        project: %{
          raw_name: "My Awesome Project",
          description: "This is a really awesome project"
        }
      )
      |> render_change()

      assert view
             |> has_element?("input[type='hidden'][value='my-awesome-project']")

      view |> form("#project-form") |> render_submit()

      projects_after = Lightning.Projects.get_projects_for_user(user)
      assert Enum.count(projects_after) == 1

      project = List.first(projects_after)

      {:ok, view, _html} = live(conn, ~p"/projects")
      assert has_element?(view, "tr#projects-table-row-#{project.id}")
    end

    test "When the user closes the modal without submitting the form, the project won't be created",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      view
      |> form("#project-form",
        project: %{
          raw_name: "My Awesome Project",
          description: "This is a really awesome project"
        }
      )
      |> render_change()

      view |> element("#cancel-project-creation") |> render_click()

      projects_after = Lightning.Projects.get_projects_for_user(user)
      assert Enum.count(projects_after) == 0
    end

    test "Users can sort the project table by name", %{conn: conn, user: user} do
      projects =
        insert_list(3, :project,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects")

      projects_sorted_by_name = get_sorted_projects_by_name(projects)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name

      view
      |> element("span[phx-click='sort'][phx-value-by='name']")
      |> render_click()

      projects_sorted_by_name_desc = get_sorted_projects_by_name(projects, :desc)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name_desc

      view
      |> element("span[phx-click='sort'][phx-value-by='name']")
      |> render_click()

      projects_sorted_by_name_asc = get_sorted_projects_by_name(projects, :asc)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name_asc
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

      projects_sorted_by_last_activity =
        get_sorted_projects_by_last_activity(projects)

      html = render(view)

      project_last_activities_from_html =
        extract_project_last_activities_from_html(html)

      assert project_last_activities_from_html ==
               projects_sorted_by_last_activity

      view
      |> element("span[phx-click='sort'][phx-value-by='last_activity']")
      |> render_click()

      projects_sorted_by_last_activity_desc =
        get_sorted_projects_by_last_activity(projects, :desc)

      html = render(view)

      project_last_activities_from_html =
        extract_project_last_activities_from_html(html)

      assert project_last_activities_from_html ==
               projects_sorted_by_last_activity_desc
    end

    test "Toggles the welcome banner", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      assert has_element?(
               view,
               "#welcome-banner-content[class~='max-h-[500px]']"
             )

      view
      |> element("button[phx-click='toggle-welcome-banner']")
      |> render_click()

      refute has_element?(
               view,
               "#welcome-banner-content[class~='max-h-[500px]']"
             )

      assert has_element?(view, "#welcome-banner-content[class~='max-h-0']")

      assert Repo.reload(user)
             |> Map.get(:preferences)
             |> Map.get("welcome.collapsed")

      view
      |> element("button[phx-click='toggle-welcome-banner']")
      |> render_click()

      assert has_element?(
               view,
               "#welcome-banner-content[class~='max-h-[500px]']"
             )

      refute Repo.reload(user)
             |> Map.get(:preferences)
             |> Map.get("welcome.collapsed")
    end

    test "Selects an arcade resource", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      view
      |> element(
        "button[phx-click='select-arcade-resource'][phx-value-resource='1']"
      )
      |> render_click()

      assert has_element?(view, "div#arcade-modal-1")
    end
  end

  defp assert_project_listed(view, project, user, last_activity_date) do
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
      if last_activity_date do
        Lightning.Helpers.format_date(last_activity_date, "%d/%m/%Y %H:%M:%S")
      else
        "No activity"
      end

    assert has_element?(
             view,
             "tr#projects-table-row-#{project.id} > td:nth-child(5)",
             formatted_date
           )
  end

  defp get_sorted_projects_by_last_activity(projects, order \\ :asc) do
    projects_with_workflows = Repo.preload(projects, :workflows)

    projects_with_workflows
    |> Enum.sort_by(
      fn project ->
        project
        |> Map.get(:workflows)
        |> Enum.map(& &1.updated_at)
        |> Enum.max(fn -> nil end)
      end,
      order
    )
    |> Enum.map(fn project ->
      last_activity =
        project
        |> Map.get(:workflows)
        |> Enum.map(& &1.updated_at)
        |> Enum.max(fn -> nil end)

      if last_activity do
        Lightning.Helpers.format_date(last_activity, "%d/%b/%Y %H:%M:%S")
      else
        "No activity"
      end
    end)
  end

  defp extract_project_last_activities_from_html(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#projects-table tr")
    |> Enum.map(fn tr ->
      tr
      |> Floki.find("td:nth-child(5)")
      |> Floki.text()
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp get_sorted_projects_by_name(projects, order \\ :asc) do
    projects
    |> Enum.sort_by(fn project -> project.name end, order)
    |> Enum.map(& &1.name)
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
end
