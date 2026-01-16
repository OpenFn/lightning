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

      assert html =~ "No projects found."
      assert html =~ "Create a new one"

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
               |> element("nav#side-menu a.menu-item", "User Profile")
               |> render_click()
               |> follow_redirect(conn, ~p"/profile")

      assert profile_live
             |> element("nav#side-menu a.menu-item", "Credentials")
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

      insert(:simple_workflow,
        project: project_1,
        updated_at: ~N[2023-10-01 12:00:00]
      )

      insert(:simple_workflow,
        project: project_1,
        updated_at: ~N[2023-10-02 12:00:00]
      )

      insert(:simple_workflow,
        project: project_2,
        updated_at: ~N[2023-10-05 12:00:00]
      )

      insert(:simple_workflow,
        project: project_2,
        updated_at: ~N[2023-10-03 12:00:00]
      )

      {:ok, view, _html} = live(conn, ~p"/projects")

      refute has_element?(view, "#projects-table-row-#{project_3.id}")

      assert_project_listed(view, project_1, user, ~N[2023-10-02 12:00:00])
      assert_project_listed(view, project_2, user, ~N[2023-10-05 12:00:00])
    end

    test "User's and support projects are listed", %{conn: conn, user: user} do
      user = Repo.update!(Changeset.change(user, %{support_user: true}))

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

      project_4 =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :owner}]
        )

      insert(:simple_workflow,
        project: project_1,
        updated_at: ~N[2023-10-01 12:00:00]
      )

      insert(:simple_workflow,
        project: project_1,
        updated_at: ~N[2023-10-02 12:00:00]
      )

      insert(:simple_workflow,
        project: project_2,
        updated_at: ~N[2023-10-05 12:00:00]
      )

      insert(:simple_workflow,
        project: project_2,
        updated_at: ~N[2023-10-03 12:00:00]
      )

      insert(:simple_workflow,
        project: project_4,
        updated_at: ~N[2025-03-28 12:00:00]
      )

      insert(:simple_workflow,
        project: project_4,
        updated_at: ~N[2025-03-28 11:00:00]
      )

      {:ok, view, _html} = live(conn, ~p"/projects")

      refute has_element?(view, "#projects-table-row-#{project_3.id}")

      assert_project_listed(view, project_1, user, ~N[2023-10-02 12:00:00])
      assert_project_listed(view, project_2, user, ~N[2023-10-05 12:00:00])
      assert_project_listed(view, project_4, user, ~N[2025-03-28 12:00:00])
    end

    test "User's projects are listed in the project combobox", %{
      conn: conn,
      user: user
    } do
      project_1 = insert(:project, project_users: [%{user: user, role: :owner}])

      project_2 = insert(:project, project_users: [%{user: user, role: :admin}])

      project_3 =
        insert(:project, project_users: [%{user: build(:user), role: :owner}])

      {:ok, view, _html} = live(conn, ~p"/projects")

      # Project picker is a React component - check data-projects contains correct project IDs
      html = render(view)
      assert html =~ project_1.id
      assert html =~ project_2.id
      refute html =~ project_3.id
    end

    test "Support user projects are listed in the project combobox", %{
      conn: conn,
      user: user
    } do
      user = Repo.update!(Changeset.change(user, %{support_user: true}))

      project_1 = insert(:project, project_users: [%{user: user, role: :owner}])

      project_2 = insert(:project, project_users: [%{user: user, role: :admin}])

      project_3 =
        insert(:project, project_users: [%{user: build(:user), role: :owner}])

      project_4 =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :admin}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects")

      # Project picker is a React component - check data-projects contains correct project IDs
      html = render(view)
      assert html =~ project_1.id
      assert html =~ project_2.id
      refute html =~ project_3.id
      # Support user should see projects with allow_support_access
      assert html =~ project_4.id
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

      projects_sorted_by_name = sorted_projects_by_name(projects)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name

      view
      |> element("a[phx-click='sort'][phx-value-by='name']")
      |> render_click()

      projects_sorted_by_name_desc = sorted_projects_by_name(projects, :desc)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name_desc

      view
      |> element("a[phx-click='sort'][phx-value-by='name']")
      |> render_click()

      projects_sorted_by_name_asc = sorted_projects_by_name(projects, :asc)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name_asc
    end

    test "Support users can sort the project table by name", %{
      conn: conn,
      user: user
    } do
      user = Repo.update!(Changeset.change(user, %{support_user: true}))

      support_project =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :admin}]
        )

      projects =
        insert_list(2, :project,
          project_users: [%{user_id: user.id, role: :admin}]
        ) ++
          [
            support_project
          ] ++
          [
            insert(:project,
              project_users: [%{user_id: user.id, role: :viewer}]
            )
          ] ++
          [
            insert(:project,
              project_users: [%{user_id: user.id, role: :editor}]
            )
          ]

      {:ok, view, _html} = live(conn, ~p"/projects")

      projects_sorted_by_name = sorted_projects_by_name(projects)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name
      assert html =~ support_project.name

      view
      |> element("a[phx-click='sort'][phx-value-by='name']")
      |> render_click()

      projects_sorted_by_name_desc = sorted_projects_by_name(projects, :desc)
      html = render(view)
      project_names_from_html = extract_project_names_from_html(html)
      assert project_names_from_html == projects_sorted_by_name_desc

      view
      |> element("a[phx-click='sort'][phx-value-by='name']")
      |> render_click()

      projects_sorted_by_name_asc = sorted_projects_by_name(projects, :asc)
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

      projects_sorted_by_last_updated_at =
        get_sorted_projects_by_last_updated_at(projects)

      html = render(view)

      project_last_activities_from_html =
        extract_project_last_activities_from_html(html)

      assert project_last_activities_from_html ==
               projects_sorted_by_last_updated_at

      view
      |> element("a[phx-click='sort'][phx-value-by='last_updated_at']")
      |> render_click()

      projects_sorted_by_last_updated_at_desc =
        get_sorted_projects_by_last_updated_at(projects, :desc)

      html = render(view)

      project_last_activities_from_html =
        extract_project_last_activities_from_html(html)

      assert project_last_activities_from_html ==
               projects_sorted_by_last_updated_at_desc
    end
  end

  defp assert_project_listed(view, project, user, max_updated_at) do
    assert has_element?(view, "tr#projects-table-row-#{project.id}")

    assert has_element?(
             view,
             "tr#projects-table-row-#{project.id}",
             project.name
           )

    role =
      project
      |> Repo.preload(:project_users)
      |> Map.get(:project_users)
      |> Enum.find(%{}, fn pu -> pu.user_id == user.id end)
      |> Map.get(:role)
      |> then(fn role ->
        if is_nil(role) and user.support_user do
          "Support"
        else
          role
          |> Atom.to_string()
          |> String.capitalize()
        end
      end)

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

    formatted_date = Calendar.strftime(max_updated_at, "%Y-%m-%d %H:%M:%S UTC")

    assert has_element?(
             view,
             "tr#projects-table-row-#{project.id} > td:nth-child(5) span[data-iso-timestamp='#{formatted_date}']",
             NaiveDateTime.to_iso8601(max_updated_at)
           )
  end

  defp get_sorted_projects_by_last_updated_at(projects, order \\ :asc) do
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
      last_updated_at =
        project
        |> Map.get(:workflows)
        |> Enum.map(& &1.updated_at)
        |> Enum.max(fn -> nil end)

      if last_updated_at do
        Lightning.Helpers.format_date(last_updated_at)
      else
        "N/A"
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

  defp sorted_projects_by_name(projects, order \\ :asc) do
    projects
    |> Enum.sort_by(fn project -> project.name end, order)
    |> Enum.map(& &1.name)
  end

  defp extract_project_names_from_html(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#projects-table tr")
    |> Enum.map(fn tr ->
      tr
      |> Floki.find("td:nth-child(1)")
      |> Floki.text()
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end
end
