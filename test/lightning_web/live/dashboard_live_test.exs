defmodule LightningWeb.DashboardLiveTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Workflows.Workflow

  require Ecto.Query

  # The page is drawn by React from data-props.
  defp props(view), do: page_props(view, "#projects-dashboard-page")
  defp projects(view), do: props(view)["projects"]

  defp project_row(view, project),
    do: Enum.find(projects(view), &(&1["id"] == project.id))

  defp create_project(view, params),
    do:
      push_page_event(view, "#projects-dashboard-page", "create_project", params)

  describe "Index" do
    setup :register_and_log_in_user

    test "User is assigned no project", %{
      conn: conn,
      user: user
    } do
      {:ok, view, html} = live(conn, ~p"/projects")

      assert %{"firstName" => first_name, "projects" => []} = props(view)
      assert first_name == user.first_name

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

      refute project_row(view, project_3)

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

      refute project_row(view, project_3)

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

      project_2 =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :owner}]
        )

      project_3 =
        insert(:project, project_users: [%{user: build(:user), role: :owner}])

      {:ok, view, _html} = live(conn, ~p"/projects")

      # Project picker is a React component - check data-projects contains correct project IDs
      html = render(view)
      assert html =~ project_1.id
      assert html =~ project_2.id
      refute html =~ project_3.id
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

      assert %{"workflowsCount" => ^workflows_count} = project_row(view, project)
    end

    test "User can create a new project", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      assert Enum.empty?(Lightning.Projects.get_projects_for_user(user))

      # The page sends the url-safe name it showed as "Your project will be named".
      assert create_project(view, %{
               "rawName" => "my-awesome-project",
               "description" => "This is a really awesome project"
             }) =~ "Project created successfully"

      assert_reply(view, %{})

      assert [project] = Lightning.Projects.get_projects_for_user(user)
      assert project.name == "my-awesome-project"
      assert project.description == "This is a really awesome project"

      # The list is refreshed without a reload.
      assert %{"name" => "my-awesome-project", "role" => "owner"} =
               project_row(view, project)
    end

    test "creating a project cannot mass-assign parent_id", %{
      conn: conn,
      user: user
    } do
      # A project the user has no role on; provisioning a sandbox under it would
      # normally require :provision_sandbox on the parent.
      other_project = insert(:project)

      {:ok, view, _html} = live(conn, ~p"/projects")

      create_project(view, %{
        "rawName" => "sneaky",
        "parent_id" => other_project.id,
        "parentId" => other_project.id,
        "project_users" => %{0 => %{"user_id" => other_project.id}}
      })

      assert [project] = Lightning.Projects.get_projects_for_user(user)
      assert project.parent_id == nil
    end

    test "Creating a project with a name that resolves to blank shows error",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      # "!!!" has no url-safe characters, so the page sends an empty name.
      create_project(view, %{"rawName" => "", "description" => ""})

      assert_reply(view, %{
        error: "Please fix the errors below.",
        fieldErrors: %{"rawName" => ["This field can't be blank."]}
      })

      assert Enum.empty?(Lightning.Projects.get_projects_for_user(user))
    end

    test "projects arrive sorted by name; the page sorts in the browser", %{
      conn: conn,
      user: user
    } do
      projects =
        insert_list(3, :project,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects")

      assert Enum.map(projects(view), & &1["name"]) ==
               projects |> Enum.map(& &1.name) |> Enum.sort()
    end
  end

  defp assert_project_listed(view, project, user, max_updated_at) do
    role =
      project
      |> Repo.preload(:project_users)
      |> Map.get(:project_users)
      |> Enum.find(%{}, fn pu -> pu.user_id == user.id end)
      |> Map.get(:role)
      |> then(fn role ->
        if is_nil(role) and user.support_user,
          do: "support",
          else: Atom.to_string(role)
      end)

    workflow_count =
      project |> Repo.preload(:workflows) |> Map.get(:workflows) |> Enum.count()

    collaborator_count =
      project
      |> Repo.preload(:project_users)
      |> Map.get(:project_users)
      |> Enum.count()

    assert %{
             "name" => name,
             "role" => ^role,
             "workflowsCount" => ^workflow_count,
             "collaboratorsCount" => ^collaborator_count,
             "lastUpdatedAt" => last_updated_at
           } = project_row(view, project)

    assert name == project.name

    assert last_updated_at ==
             max_updated_at
             |> DateTime.from_naive!("Etc/UTC")
             |> DateTime.to_iso8601()
  end
end
