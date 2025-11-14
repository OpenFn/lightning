defmodule LightningWeb.ProjectLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Phoenix.Component
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.Factories
  import LightningWeb.CredentialLiveHelpers

  import Lightning.ApplicationHelpers,
    only: [put_temporary_env: 3]

  import Lightning.GithubHelpers
  import Swoosh.TestAssertions

  import Mock
  import Mox

  alias Lightning.Auditing.Audit
  alias Lightning.Name
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Repo

  setup :stub_usage_limiter_ok
  setup :verify_on_exit!

  @create_attrs %{raw_name: "some name"}
  @invalid_attrs %{raw_name: nil}

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the index page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/projects") |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end

    test "cannot access the new page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/projects/new")
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a super user" do
    setup [:register_and_log_in_superuser, :create_project_for_current_user]

    test "renders a banner when run limit has been reached", %{
      conn: conn,
      project: %{id: project_id}
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :check_limits,
        &Lightning.Extensions.StubUsageLimiter.check_limits/1
      )

      {:ok, _live, html} =
        live(conn, ~p"/projects/#{project_id}/settings")

      assert html =~ "Some banner text"
    end

    test "lists all projects", %{conn: conn, project: project} do
      {:ok, _index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"
      assert html =~ project.name
    end

    test "fails to save a project with no members", %{conn: conn} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert index_live |> element("a", "New Project") |> render_click() =~
               "Projects"

      assert_patch(index_live, Routes.project_index_path(conn, :new))

      html =
        index_live
        |> form("#project-form", project: @create_attrs)
        |> render_submit()

      assert html =~
               "Every project must have exactly one owner. Please specify one below."
    end

    test "saves new project with members", %{conn: conn} do
      user_1 = insert(:user, first_name: "1st", last_name: "user")
      user_2 = insert(:user, first_name: "another", last_name: "person")

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert index_live |> element("a", "New Project") |> render_click() =~
               "Projects"

      assert_patch(index_live, Routes.project_index_path(conn, :new))

      # error for no owner is not shown until you make a change
      refute render(index_live) =~
               "Every project must have exactly one owner. Please specify one below."

      assert index_live
             |> form("#project-form", project: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert render(index_live) =~
               "Every project must have exactly one owner. Please specify one below."

      user_1_index = find_user_index_in_list(index_live, user_1)
      user_2_index = find_user_index_in_list(index_live, user_2)

      # error for multiple owners is displayed
      html =
        index_live
        |> form("#project-form",
          project: %{
            "project_users" => %{
              user_1_index => %{"user_id" => user_1.id, "role" => "owner"},
              user_2_index => %{"user_id" => user_2.id, "role" => "owner"}
            }
          }
        )
        |> render_change()

      assert html =~ "A project can have only one owner."

      index_live
      |> form("#project-form",
        project:
          Map.merge(@create_attrs, %{
            "project_users" => %{
              user_1_index => %{"user_id" => user_1.id, "role" => "owner"},
              user_2_index => %{"user_id" => user_2.id, "role" => "editor"}
            }
          })
      )
      |> render_change()

      index_live |> form("#project-form") |> render_submit()

      assert_patch(index_live, Routes.project_index_path(conn, :index))
      assert render(index_live) =~ "Project created successfully"

      project_name = String.replace(@create_attrs.raw_name, " ", "-")

      assert_email_sent(
        to: [Swoosh.Email.Recipient.format(user_1)],
        subject: "You now have access to \"#{project_name}\""
      )

      assert_email_sent(
        to: [Swoosh.Email.Recipient.format(user_2)],
        subject: "You now have access to \"#{project_name}\""
      )
    end

    test "project owners can delete a project from the settings page",
         %{
           conn: conn,
           project: project
         } do
      {conn, _user} = setup_project_user(conn, project, :owner)
      {:ok, index_live, html} = live(conn, ~p"/projects/#{project.id}/settings")

      assert html =~ "Deleting your project is irreversible"
      assert index_live |> element("a", "Delete project") |> has_element?()

      {:ok, delete_project_modal, html} =
        live(conn, ~p"/projects/#{project.id}/settings/delete")

      assert html =~ "Enter the project name to confirm deletion"

      {:ok, _delete_project_modal, html} =
        delete_project_modal
        |> form("#scheduled_deletion_form",
          project: %{
            name_confirmation: project.name
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/projects")

      assert html =~ "Project scheduled for deletion"
    end

    test "project members can export a project", %{conn: conn, project: project} do
      {:ok, index_live, html} = live(conn, ~p"/projects/#{project.id}/settings")

      assert html =~
               "Export your project as code, to save this version or edit your project locally"

      assert index_live
             |> element(~s{a[target="_blank"]}, "Export project")
             |> has_element?()

      assert index_live
             |> element(~s{a[target="_blank"]}, "Export project")
             |> render_click()
             |> follow_redirect(conn, "/download/yaml?id=#{project.id}")
    end

    test "project members with role other than owner can't delete a project from the settings page",
         %{
           conn: conn,
           project: project
         } do
      ~w(editor admin viewer)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        {:ok, index_live, html} =
          live(conn, ~p"/projects/#{project.id}/settings")

        refute html =~ "Deleting your project is irreversible"

        refute index_live
               |> element("button", "Delete project")
               |> has_element?()

        {:ok, _delete_project_modal, html} =
          live(conn, ~p"/projects/#{project.id}/settings/delete")
          |> follow_redirect(conn, ~p"/projects/#{project.id}/settings")

        assert html =~ "You are not authorize to perform this action"
      end)
    end

    test "allows a superuser to schedule projects for deletion in the projects list",
         %{
           conn: conn,
           project: project
         } do
      {:ok, index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"

      {:ok, form_live, _} =
        index_live
        |> element("#delete-#{project.id}", "Delete")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :delete, project)
        )

      assert form_live
             |> form("#scheduled_deletion_form",
               project: %{name_confirmation: "invalid name"}
             )
             |> render_change() =~
               "Enter the project name to confirm deletion"

      {:ok, _index_live, html} =
        form_live
        |> form("#scheduled_deletion_form",
          project: %{
            name_confirmation: project.name
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Project scheduled for deletion"
    end

    test "allows superuser to click cancel for closing user deletion modal", %{
      conn: conn,
      project: project
    } do
      {:ok, index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"

      {:ok, form_live, _} =
        index_live
        |> element("#delete-#{project.id}", "Delete")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :delete, project)
        )

      {:ok, index_live, _html} =
        form_live
        |> element("button", "Cancel")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :index)
        )

      assert has_element?(index_live, "#delete-#{project.id}")
    end

    test "allows a superuser to cancel scheduled deletion on a project", %{
      conn: conn
    } do
      project =
        project_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index), on_error: :raise)

      assert index_live
             |> element("#cancel-deletion-#{project.id}", "Cancel deletion")
             |> render_click() =~ "Project deletion canceled"
    end

    test "allows a superuser to perform delete now action on a scheduled for deletion project",
         %{
           conn: conn
         } do
      project =
        project_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index), on_error: :raise)

      {:ok, form_live, _html} =
        index_live
        |> element("#delete-now-#{project.id}", "Delete now")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :delete, project)
        )

      {:ok, index_live, html} =
        form_live
        |> form("#scheduled_deletion_form",
          project: %{
            name_confirmation: project.name
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.project_index_path(conn, :index))

      assert html =~
               "Project deletion started. This may take a while to complete."

      refute index_live |> element("project-#{project.id}") |> has_element?()
    end

    test "Edits a project", %{conn: conn, user: superuser} do
      user1 = insert(:user, first_name: "Alice", last_name: "Owner")
      user2 = insert(:user, first_name: "Bob", last_name: "Viewer")

      project =
        insert(:project, project_users: [%{role: :owner, user_id: user1.id}])

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      view
      |> form("#project-form",
        project: %{
          "project_users" => %{
            find_user_index_in_list(view, user1) => %{
              "user_id" => user1.id,
              "role" => "owner"
            },
            find_user_index_in_list(view, user2) => %{
              "user_id" => user2.id,
              "role" => "viewer"
            }
          }
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/settings/projects")
      assert render(view) =~ "Project updated successfully"

      updated_project =
        Repo.preload(project, [:project_users], force: true)

      assert Enum.count(updated_project.project_users) == 2

      for p_user <- updated_project.project_users do
        assert p_user.user_id in [user1.id, user2.id]
        refute p_user.user_id == superuser.id
      end
    end

    test "sorting projects by name works correctly", %{conn: conn} do
      _project_a = insert(:project, name: "alpha-project")
      _project_b = insert(:project, name: "beta-project")
      _project_c = insert(:project, name: "charlie-project")

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      # Click name header to sort descending (first click)
      index_live
      |> element("th a", "Name")
      |> render_click()

      html = render(index_live)

      # Check that projects appear in reverse name order
      [alpha_pos, beta_pos, charlie_pos] =
        get_element_order(html, [
          "alpha-project",
          "beta-project",
          "charlie-project"
        ])

      assert charlie_pos < beta_pos
      assert beta_pos < alpha_pos

      # Click name header again to sort ascending
      index_live
      |> element("th a", "Name")
      |> render_click()

      html = render(index_live)

      # Check that projects appear in name alphabetical order
      assert assert_elements_in_order(html, [
               "alpha-project",
               "beta-project",
               "charlie-project"
             ])
    end

    test "sorting projects by created date works correctly", %{conn: conn} do
      # Create projects with different dates
      _project_old =
        insert(:project,
          name: "old-project",
          inserted_at: ~N[2023-01-01 00:00:00]
        )

      _project_new =
        insert(:project,
          name: "new-project",
          inserted_at: ~N[2023-12-01 00:00:00]
        )

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      # Click created at header to sort
      index_live
      |> element("th a", "Created At")
      |> render_click()

      html = render(index_live)

      # Old project should appear first when sorted by created date ascending
      assert assert_elements_in_order(html, ["old-project", "new-project"])
    end

    test "filtering projects by search term works correctly", %{conn: conn} do
      project_a =
        insert(:project, name: "alpha-project", description: "First project")

      _project_b =
        insert(:project, name: "beta-project", description: "Second project")

      # Add an owner to project_a so it shows up in owner search
      user_owner = insert(:user, first_name: "John", last_name: "Owner")
      insert(:project_user, project: project_a, user: user_owner, role: :owner)

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      # Filter by project name
      index_live
      |> element("input[name=filter]")
      |> render_keyup(%{"key" => "a", "value" => "alpha"})

      html = render(index_live)
      assert html =~ "alpha-project"
      refute html =~ "beta-project"

      # Filter by description
      index_live
      |> element("input[name=filter]")
      |> render_keyup(%{"key" => "f", "value" => "First"})

      html = render(index_live)
      assert html =~ "alpha-project"
      refute html =~ "beta-project"

      # Filter by owner name
      index_live
      |> element("input[name=filter]")
      |> render_keyup(%{"key" => "j", "value" => "John"})

      html = render(index_live)
      assert html =~ "alpha-project"
      refute html =~ "beta-project"

      # Clear filter
      index_live
      |> render_click("clear_filter")

      html = render(index_live)
      assert html =~ "alpha-project"
      assert html =~ "beta-project"
    end

    test "project filter input shows correct placeholder and clear button", %{
      conn: conn
    } do
      {:ok, index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      # Check filter input is present
      assert has_element?(index_live, "input[name=filter]")

      # Initially clear button should be hidden
      assert html =~ "class=\"hidden\""

      # Type in filter
      index_live
      |> element("input[name=filter]")
      |> render_keyup(%{"key" => "a", "value" => "test"})

      html = render(index_live)

      # Clear button should now be visible (not hidden)
      refute html =~ "class=\"hidden\""
      assert has_element?(index_live, "a[phx-click='clear_filter']")
    end

    test "adding collaborators to project works correctly", %{conn: conn} do
      user1 = insert(:user, first_name: "Alice", last_name: "Smith")
      user2 = insert(:user, first_name: "Bob", last_name: "Jones")
      user3 = insert(:user, first_name: "Charlie", last_name: "Brown")

      # Create project with only user1 as owner
      project = insert(:project)
      insert(:project_user, project: project, user: user1, role: :owner)

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      # Find user indices in the form
      user2_index = find_user_index_in_list(view, user2)
      user3_index = find_user_index_in_list(view, user3)

      # Add user2 as editor and user3 as viewer
      view
      |> form("#project-form",
        project: %{
          "project_users" => %{
            user2_index => %{"user_id" => user2.id, "role" => "editor"},
            user3_index => %{"user_id" => user3.id, "role" => "viewer"}
          }
        }
      )
      |> render_submit()

      # Check that users were added
      updated_project = Repo.preload(project, [:project_users], force: true)

      user_roles =
        Enum.map(updated_project.project_users, &{&1.user_id, &1.role})

      assert {user2.id, :editor} in user_roles
      assert {user3.id, :viewer} in user_roles

      # Check that newly added collaborators have failure_alert defaulting to false
      user2_project_user =
        Enum.find(updated_project.project_users, &(&1.user_id == user2.id))

      user3_project_user =
        Enum.find(updated_project.project_users, &(&1.user_id == user3.id))

      assert user2_project_user.failure_alert == false
      assert user3_project_user.failure_alert == false
    end

    test "removing collaborators from project works correctly", %{conn: conn} do
      user1 = insert(:user, first_name: "Alice", last_name: "Smith")
      user2 = insert(:user, first_name: "Bob", last_name: "Jones")
      user3 = insert(:user, first_name: "Charlie", last_name: "Brown")

      # Create project with all three users
      project = insert(:project)
      insert(:project_user, project: project, user: user1, role: :owner)
      insert(:project_user, project: project, user: user2, role: :editor)
      insert(:project_user, project: project, user: user3, role: :viewer)

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      # Find user indices in the form
      user2_index = find_user_index_in_list(view, user2)
      user3_index = find_user_index_in_list(view, user3)

      # Remove user2 and user3 by setting their roles to empty
      view
      |> form("#project-form",
        project: %{
          "project_users" => %{
            user2_index => %{"user_id" => user2.id, "role" => ""},
            user3_index => %{"user_id" => user3.id, "role" => ""}
          }
        }
      )
      |> render_submit()

      # Check that users were removed
      updated_project = Repo.preload(project, [:project_users], force: true)
      user_ids = Enum.map(updated_project.project_users, & &1.user_id)

      assert user1.id in user_ids
      refute user2.id in user_ids
      refute user3.id in user_ids
    end

    test "changing collaborator roles works correctly", %{conn: conn} do
      user1 = insert(:user, first_name: "Alice", last_name: "Smith")
      user2 = insert(:user, first_name: "Bob", last_name: "Jones")

      # Create project with user1 as owner and user2 as viewer
      project = insert(:project)
      insert(:project_user, project: project, user: user1, role: :owner)
      insert(:project_user, project: project, user: user2, role: :viewer)

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      # Find user2's index
      user2_index = find_user_index_in_list(view, user2)

      # Change user2 from viewer to admin
      view
      |> form("#project-form",
        project: %{
          "project_users" => %{
            user2_index => %{"user_id" => user2.id, "role" => "admin"}
          }
        }
      )
      |> render_submit()

      # Check that user2's role was changed
      updated_project = Repo.preload(project, [:project_users], force: true)

      user2_project_user =
        Enum.find(updated_project.project_users, &(&1.user_id == user2.id))

      assert user2_project_user.role == :admin
    end

    test "project user management form has sorting and filtering", %{conn: conn} do
      user1 =
        insert(:user,
          first_name: "Alice",
          last_name: "Alpha",
          email: "alice@example.com"
        )

      _user2 =
        insert(:user,
          first_name: "Bob",
          last_name: "Beta",
          email: "bob@example.com"
        )

      _user3 =
        insert(:user,
          first_name: "Charlie",
          last_name: "Gamma",
          email: "charlie@example.com"
        )

      project = insert(:project)
      insert(:project_user, project: project, user: user1, role: :owner)

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      # Check that filter input is present
      assert has_element?(view, "input[name=filter]")

      # Test filtering by name
      view
      |> element("input[name=filter]")
      |> render_keyup(%{"value" => "Alice"})

      html = render(view)
      assert html =~ "Alice Alpha"
      refute html =~ "Bob Beta"
      refute html =~ "Charlie Gamma"

      # Clear the filter first to test sorting
      view
      |> element("#clear_filter_button")
      |> render_click()

      # Test sorting by name
      view
      |> element("th a", "NAME")
      |> render_click()

      html = render(view)
      # Check that users are sorted in descending order (first click)
      [charlie_pos, bob_pos, alice_pos] =
        get_element_order(
          html,
          ["Charlie Gamma", "Bob Beta", "Alice Alpha"],
          "#project_users_table tbody tr"
        )

      # First click sorts in descending order: Charlie, Bob, Alice
      assert charlie_pos < bob_pos
      assert bob_pos < alice_pos
    end
  end

  describe "download exported project" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    setup %{project: project} do
      {:ok, workflow: insert(:simple_workflow, project: project)}
    end

    test "having edge with condition_type=always", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :always})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: always]
    end

    test "having edge with condition_type=on_job_success", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :on_job_success})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: on_job_success]
    end

    test "having edge with condition_type=on_job_failure", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :on_job_failure})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: on_job_failure]
    end

    test "having edge with condition_type=js_expression", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{
        condition_type: :js_expression,
        condition_label: "not underaged",
        condition_expression: "state.data.age > 18"
      })
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: js_expression]
      assert response =~ ~S[condition_label: not underaged]

      assert response =~
               ~s[condition_expression: |\n          state.data.age > 18]
    end
  end

  describe "projects picker dropdown" do
    setup :register_and_log_in_user

    test "Access project settings page", %{conn: conn, user: user} do
      another_user = insert(:user)

      project_1 =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id}]
        )

      project_2 =
        insert(:project,
          name: "project-2",
          project_users: [%{user_id: user.id}]
        )

      project_3 =
        insert(:project,
          name: "project-3",
          project_users: [%{user_id: another_user.id}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project_1}/w", on_error: :raise)

      assert view
             |> element(
               ~s{a[href="#{~p"/projects/#{project_1.id}/w"}"]},
               ~r/project-1/
             )
             |> has_element?()

      assert view
             |> element(
               "#option-#{project_2.id}",
               ~r/project-2/
             )
             |> has_element?()

      refute view
             |> element(
               "#option-#{project_3.id}",
               ~r/project-3/
             )
             |> has_element?()

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project_1}/w", on_error: :raise)

      assert html =~ project_1.name

      assert view
             |> element("input[id='combobox'][value='#{project_1.name}']")
             |> has_element?()

      assert view
             |> element("#option-#{project_2.id}")
             |> has_element?()

      refute view
             |> element("#option-#{project_3.id}")
             |> has_element?()

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project_2}/w", on_error: :raise)

      assert html =~ project_2.name

      assert view
             |> element("input[id='combobox'][value='#{project_2.name}']")
             |> has_element?()

      assert view
             |> element("#option-#{project_1.id}")
             |> has_element?()

      refute view
             |> element("#option-#{project_3.id}")
             |> has_element?()

      assert live(conn, ~p"/projects/#{project_3}/w", on_error: :raise) ==
               {:error,
                {:redirect, %{flash: %{"nav" => :not_found}, to: "/projects"}}}
    end
  end

  describe "projects settings page" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "access project settings page", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"
    end

    test "access project settings page by support user", %{
      conn: conn,
      project: project,
      user: user
    } do
      _user = Repo.update!(Changeset.change(user, %{support_user: true}))

      project =
        Repo.update!(Changeset.change(project, %{allow_support_access: true}))

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"
    end

    @tag role: :admin
    test "project admin can view project collaboration page", %{
      conn: conn,
      project: project
    } do
      project_user =
        Lightning.Projects.get_project_users!(project.id)
        |> List.first()

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Collaborator"
      assert html =~ "Role"

      assert html =~
               "#{project_user.user.first_name} #{project_user.user.last_name}"
               |> Phoenix.HTML.Safe.to_iodata()
               |> to_string()

      assert html =~ project_user.role |> Atom.to_string() |> String.capitalize()

      assert html =~
               "#{project_user.user.first_name} #{project_user.user.last_name}"
    end

    test "project admin can view project credentials page",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, credential} =
        Lightning.Credentials.create_credential(%{
          body: %{},
          name: "some name",
          user_id: user.id,
          schema: "raw",
          project_credentials: [
            %{project_id: project.id}
          ]
        })

      credential = Lightning.Repo.preload(credential, :user)

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ "Name"
      assert html =~ "Type"
      assert html =~ "Owner"
      assert html =~ "Environment"

      assert html =~
               credential.name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

      assert html =~ credential.schema
      assert html =~ credential.name
      assert html =~ credential.user.email
    end

    test "authorized project users can create new credentials in the project credentials page",
         %{
           conn: conn,
           user: user
         } do
      [:admin, :editor]
      |> Enum.each(fn role ->
        project =
          insert(:project,
            name: "project-1",
            project_users: [%{user_id: user.id, role: role}]
          )

        {:ok, view, html} =
          live(conn, ~p"/projects/#{project}/settings#credentials",
            on_error: :raise
          )

        credential_name = Lightning.Name.generate()

        refute html =~ credential_name

        view |> element("#new-credential-option-menu-item") |> render_click()

        view |> select_credential_type("http")
        view |> click_continue()

        assert view
               |> fill_credential(%{
                 name: credential_name,
                 body: %{
                   username: "foo",
                   password: "bar",
                   baseUrl: "http://localhost"
                 }
               })

        {:ok, _view, html} =
          view
          |> click_save()
          |> follow_redirect(
            conn,
            ~p"/projects/#{project}/settings#credentials"
          )

        assert html =~ credential_name
      end)
    end

    test "support users can create new credentials in the project credentials page",
         %{
           conn: conn,
           user: user
         } do
      _user = Repo.update!(Changeset.change(user, %{support_user: true}))

      project =
        insert(:project,
          name: "project-1",
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :owner}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      credential_name = Lightning.Name.generate()

      refute html =~ credential_name

      # button is not disabled
      refute view |> element("#new-credential-option-menu-item") |> render() =~
               "disabled"

      view |> element("#new-credential-option-menu-item") |> render_click()

      view |> select_credential_type("http")
      view |> click_continue()

      assert view
             |> fill_credential(%{
               name: credential_name,
               body: %{
                 username: "foo",
                 password: "bar",
                 baseUrl: "http://localhost"
               }
             })

      {:ok, _view, html} =
        view
        |> click_save()
        |> follow_redirect(
          conn,
          ~p"/projects/#{project}/settings#credentials"
        )

      assert html =~ credential_name
    end

    test "non authorized project users can't create new credentials in the project credentials page",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # button appears disabled
      assert view |> element("#new-credential-option-menu-item") |> render() =~
               "cursor-not-allowed"

      # send event anyway
      view
      |> with_target("#credentials-index-component")
      |> render_click("show_modal", %{"target" => "new_credential"})

      # for some reason the #credentials is not included in the url in tests
      assert_patched(view, ~p"/projects/#{project}/settings")

      assert render(view) =~ "You are not authorized to perform this action"
    end

    test "click on cancel button to close credential creation modal", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # open modal
      view |> element("#new-credential-option-menu-item") |> render_click()

      assert has_element?(view, "#new-credential-modal")

      view
      |> element("#cancel-credential-type-picker", "Cancel")
      |> render_click()

      refute has_element?(view, "#new-credential-modal")
    end

    test "project admin can see keychain credential option in dropdown menu",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Verify the new keychain credential option is in the page
      assert has_element?(
               view,
               "#new-keychain-credential-option-menu-item",
               "Keychain"
             )
    end

    test "project admin can view keychain credentials table", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      keychain_credential =
        insert(:keychain_credential,
          name: "Test Keychain",
          path: "$.organization.id",
          project: project,
          created_by: user
        )

      # Create another project and keychain credential that should NOT be visible
      other_project =
        insert(:project,
          name: "other-project",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      other_keychain_credential =
        insert(:keychain_credential,
          name: "Other Project Keychain",
          path: "$.user.department",
          project: other_project,
          created_by: user
        )

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ "Keychain Credentials"
      # Should see the keychain credential for this project
      assert html =~ keychain_credential.name
      assert html =~ keychain_credential.path
      # Should NOT see the keychain credential from the other project
      refute html =~ other_keychain_credential.name
      refute html =~ other_keychain_credential.path
    end

    test "project admin can edit keychain credentials", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      keychain_credential =
        insert(:keychain_credential,
          name: "Test Keychain",
          path: "$.organization.id",
          project: project,
          created_by: user
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Verify the keychain credential appears with edit actions
      assert html =~ "Test Keychain"
      assert html =~ "$.organization.id"
      assert html =~ "Actions"

      html =
        view
        |> element("#keychain-credential-actions-#{keychain_credential.id}-edit")
        |> render_click()

      # Verify that edit modal component is present in the page
      assert html =~ "edit-keychain-credential-#{keychain_credential.id}-modal"
    end

    test "project viewer cannot edit keychain credentials", %{
      conn: conn,
      user: user
    } do
      admin_user = insert(:user)

      project =
        insert(:project,
          name: "project-1",
          project_users: [
            %{user_id: user.id, role: :viewer},
            %{user_id: admin_user.id, role: :admin}
          ]
        )

      keychain_credential =
        insert(:keychain_credential,
          name: "Test Keychain",
          path: "$.organization.id",
          project: project,
          created_by: admin_user
        )

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ "Keychain Credentials"
      assert html =~ keychain_credential.name
      # Verify the actions dropdown is not present for viewers
      refute html =~
               "keychain-credential-actions-#{keychain_credential.id}-dropdown"
    end

    test "project admin can delete keychain credentials", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      keychain_credential =
        insert(:keychain_credential,
          name: "Test Keychain",
          path: "$.organization.id",
          project: project,
          created_by: user
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Verify the keychain credential appears with delete actions
      assert html =~ keychain_credential.name
      assert html =~ "Actions"

      html =
        view
        |> element(
          "#keychain-credential-actions-#{keychain_credential.id}-delete"
        )
        |> render_click()

      # Verify that delete modal component is present in the page
      assert html =~ "delete-keychain-credential-#{keychain_credential.id}-modal"

      html =
        view
        |> element(
          "#delete-keychain-credential-#{keychain_credential.id}-modal_confirm_button"
        )
        |> render_click()

      # close the modal, which gets the
      # view
      # |> with_target("#credentials-index-component")
      # |> render_hook("close_active_modal", %{})

      # open_browser(view)
      # Verify the flash message appears
      assert html =~ "Keychain credential deleted"

      html =
        view
        |> element("#keychain-credentials-table-container")
        |> render()

      # Verify the keychain credential is removed from the UI
      refute html =~ keychain_credential.name
    end

    test "project editor cannot edit keychain credentials", %{
      conn: conn,
      user: user
    } do
      admin_user = insert(:user)

      project =
        insert(:project,
          name: "project-1",
          project_users: [
            %{user_id: user.id, role: :editor},
            %{user_id: admin_user.id, role: :admin}
          ]
        )

      keychain_credential =
        insert(:keychain_credential,
          name: "Test Keychain",
          path: "$.organization.id",
          project: project,
          created_by: admin_user
        )

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ "Keychain Credentials"
      assert html =~ keychain_credential.name

      # Verify the actions dropdown is not present for editors (only owners/admins)
      refute html =~
               "keychain-credential-actions-#{keychain_credential.id}-dropdown"
    end

    test "keychain credential delete permissions by role via UI", %{
      conn: conn,
      user: user
    } do
      admin_user = insert(:user)
      editor_user = insert(:user)
      viewer_user = insert(:user)

      project =
        insert(:project,
          name: "project-1",
          project_users: [
            %{user_id: user.id, role: :owner},
            %{user_id: admin_user.id, role: :admin},
            %{user_id: editor_user.id, role: :editor},
            %{user_id: viewer_user.id, role: :viewer}
          ]
        )

      keychain_credential =
        insert(:keychain_credential,
          name: "Test Keychain",
          path: "$.organization.id",
          project: project,
          created_by: admin_user
        )

      # Test as owner - should see actions dropdown
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials")

      assert html =~
               "keychain-credential-actions-#{keychain_credential.id}-dropdown"

      # Test as admin - should see actions dropdown
      admin_conn = log_in_user(build_conn(), admin_user)

      {:ok, _view, html} =
        live(admin_conn, ~p"/projects/#{project}/settings#credentials")

      assert html =~
               "keychain-credential-actions-#{keychain_credential.id}-dropdown"

      # Test as editor - should NOT see actions dropdown
      editor_conn = log_in_user(build_conn(), editor_user)

      {:ok, _view, html} =
        live(editor_conn, ~p"/projects/#{project}/settings#credentials")

      refute html =~
               "keychain-credential-actions-#{keychain_credential.id}-dropdown"

      # Test as viewer - should NOT see actions dropdown
      viewer_conn = log_in_user(build_conn(), viewer_user)

      {:ok, _view, html} =
        live(viewer_conn, ~p"/projects/#{project}/settings#credentials")

      refute html =~
               "keychain-credential-actions-#{keychain_credential.id}-dropdown"
    end

    test "project admin can create keychain credential from settings", %{
      conn: conn,
      user: user
    } do
      credential = insert(:credential, user: user)

      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      insert(:project_credential, project: project, credential: credential)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Open create keychain credential modal
      html =
        view
        |> element("#new-keychain-credential-option-menu-item")
        |> render_click()

      # Verify modal opened and form is present (testing from_collab_editor: false path)
      assert html =~ "Keychain"
      assert html =~ "keychain-credential-form-new"

      # Submit form with name and path (covers save handler and push_event)
      view
      |> form("#keychain-credential-form-new", %{
        "keychain_credential" => %{
          "name" => "My Keychain Credential",
          "path" => "$.user_id"
        }
      })
      |> render_submit()

      # Verify keychain credential was created (proves the form submitted successfully)
      keychain_credential =
        Repo.get_by(
          Lightning.Credentials.KeychainCredential,
          name: "My Keychain Credential"
        )

      assert keychain_credential
      assert keychain_credential.created_by_id == user.id
    end

    test "project admin can update keychain credential from settings", %{
      conn: conn,
      user: user
    } do
      credential_1 = insert(:credential, user: user)

      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      insert(:project_credential, project: project, credential: credential_1)

      keychain_credential =
        insert(:keychain_credential,
          created_by: user,
          project: project,
          name: "Original Name",
          path: "$.org_id"
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Open edit keychain credential modal
      html =
        view
        |> element(
          "a#keychain-credential-actions-#{keychain_credential.id}-edit"
        )
        |> render_click()

      # Verify modal opened (testing from_collab_editor: false path)
      assert html =~ "Keychain"
      assert html =~ "keychain-credential-form-#{keychain_credential.id}"

      # Update the form (covers update handler and push_event)
      view
      |> form("#keychain-credential-form-#{keychain_credential.id}", %{
        "keychain_credential" => %{
          "name" => "Updated Name",
          "path" => "$.updated_path"
        }
      })
      |> render_submit()

      # Verify keychain credential was updated (proves the form submitted successfully)
      updated =
        Repo.get(
          Lightning.Credentials.KeychainCredential,
          keychain_credential.id
        )

      assert updated.name == "Updated Name"
      assert updated.path == "$.updated_path"
    end

    test "shows validation errors when creating invalid keychain credential",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Open create keychain credential modal
      view
      |> element("#new-keychain-credential-option-menu-item")
      |> render_click()

      # Submit empty form (covers validation error path)
      html =
        view
        |> form("#keychain-credential-form-new", %{
          "keychain_credential" => %{
            "name" => "",
            "path" => ""
          }
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "viewer cannot create keychain credential (authorization check)", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Button appears disabled for viewers
      assert view
             |> element("#new-keychain-credential-option-menu-item")
             |> render() =~ "cursor-not-allowed"

      # Send event anyway (bypassing UI)
      view
      |> with_target("#credentials-index-component")
      |> render_click("show_modal", %{"target" => "new_keychain_credential"})

      # Authorization check in credential_index_component blocks it
      assert render(view) =~ "You are not authorized to perform this action"
    end

    test "viewer cannot edit keychain credential (authorization check)", %{
      conn: conn,
      user: viewer_user
    } do
      admin_user = insert(:user)

      project =
        insert(:project,
          name: "project-1",
          project_users: [
            %{user_id: admin_user.id, role: :admin},
            %{user_id: viewer_user.id, role: :viewer}
          ]
        )

      keychain_credential =
        insert(:keychain_credential,
          created_by: admin_user,
          project: project,
          name: "Protected",
          path: "$.secret"
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      # Viewer sees the credential but not the edit button
      assert html =~ "Protected"

      refute html =~
               "keychain-credential-actions-#{keychain_credential.id}-dropdown"

      # Send edit event anyway (bypassing UI)
      view
      |> with_target("#credentials-index-component")
      |> render_click("edit_keychain_credential", %{
        "id" => keychain_credential.id
      })

      # Authorization check in credential_index_component blocks it
      assert render(view) =~ "You are not authorized to perform this action"
    end

    test "project admin can't edit project name and description with invalid data",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"

      invalid_project_name = %{
        name: "some name"
      }

      invalid_project_description = %{
        description:
          Enum.map(1..250, fn _ ->
            Enum.random(Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9))
          end)
          |> to_string()
      }

      assert view
             |> form("#project-settings-form", project: invalid_project_name)
             |> render_change() =~ "has invalid format"

      assert view
             |> form("#project-settings-form",
               project: invalid_project_description
             )
             |> render_change() =~ "should be at most 240 character(s)"

      assert view |> has_element?("button[disabled][type=submit]")
    end

    test "project admin can edit project name and description with valid data",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"

      valid_project_attrs = %{
        name: "somename",
        description: "some description"
      }

      assert view
             |> form("#project-settings-form", project: valid_project_attrs)
             |> render_submit() =~ "Project updated successfully"

      assert %{
               name: "somename",
               description: "some description"
             } = Repo.get!(Project, project.id)
    end

    test "project admin can edit project concurrency with valid data",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"

      assert view
             |> form("#project-concurrency-form")
             |> render_submit(%{project: %{concurrency: "1"}}) =~
               "Project updated successfully"

      assert %{concurrency: 1} = Repo.get!(Project, project.id)
    end

    test "only users with admin level on project can edit project details", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"

      assert view
             |> has_element?("input[disabled='disabled'][name='project[name]']")

      assert view
             |> has_element?(
               "textarea[disabled='disabled'][name='project[description]']"
             )

      assert view |> has_element?("button[disabled][type=submit]")

      assert view |> render_click("save", %{"project" => %{}}) =~
               "You are not authorized to perform this action."
    end

    test "support users cannot edit project details", %{
      conn: conn,
      user: user
    } do
      _user = Repo.update!(Changeset.change(user, %{support_user: true}))

      project =
        insert(:project,
          name: "project-1",
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :owner}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"

      assert view
             |> has_element?("input[disabled='disabled'][name='project[name]']")

      assert view
             |> has_element?(
               "textarea[disabled='disabled'][name='project[description]']"
             )

      assert view |> has_element?("button[disabled][type=submit]")

      assert view |> render_click("save", %{"project" => %{}}) =~
               "You are not authorized to perform this action."
    end

    test "project members can edit their own digest frequency and failure alert settings",
         %{conn: conn, user: authenticated_user} do
      unauthenticated_user = user_fixture(first_name: "Bob")

      project =
        insert(:project,
          name: "project-1",
          project_users: [
            %{
              user_id: authenticated_user.id,
              digest: :never,
              failure_alert: false
            },
            %{
              user_id: unauthenticated_user.id,
              digest: :daily,
              failure_alert: true
            }
          ]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings" <> "#collaboration",
          on_error: :raise
        )

      authenticated_user_project_user =
        project.project_users
        |> Enum.find(fn pu -> pu.user_id == authenticated_user.id end)

      unauthenticated_user_project_user =
        project.project_users
        |> Enum.find(fn pu -> pu.user_id == unauthenticated_user.id end)

      assert_raise ArgumentError, fn ->
        view
        |> element("#project_user-#{unauthenticated_user_project_user.id}")
        |> render_click()
      end

      form_id = "#failure-alert-#{authenticated_user_project_user.id}"

      assert view |> has_element?("#{form_id} option[selected]", "Disabled")

      refute view
             |> form(form_id, %{"failure_alert" => "false"})
             |> render_change() =~ "Project user updated successfuly"

      assert view
             |> form(form_id, %{"failure_alert" => "true"})
             |> render_change() =~ "Project user updated successfuly"

      assert view
             |> has_element?(
               "#failure-alert-#{authenticated_user_project_user.id} option[selected]",
               "Enabled"
             )

      view
      |> element("[data-flash-kind='info']")
      |> render_hook("lv:clear-flash")

      form_id = "#digest-#{authenticated_user_project_user.id}"

      assert view |> has_element?("#{form_id} option[selected]", "Never")

      refute view
             |> element(form_id)
             |> render_change(%{"digest" => "never"}) =~
               "Project user updated successfuly"

      assert view
             |> form(form_id, %{"digest" => "daily"})
             |> render_change() =~ "Project user updated successfuly"

      assert view |> has_element?("#{form_id} option[selected]", "Daily")
    end

    test "all project users can view project security page",
         %{
           conn: conn
         } do
      project = insert(:project)

      # project editor and viewer cannot see the settings page

      [:admin, :owner, :editor, :viewer]
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        {:ok, view, html} =
          live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

        assert has_element?(view, "#security-tab")
        assert html =~ "Multi-Factor Authentication"
      end)
    end

    test "project admin can toggle MFA requirement",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          project_users: [%{user: user, role: :admin}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"

      assert view
             |> element("#toggle-mfa-switch")
             |> render_click() =~ "Project MFA requirement updated successfully"
    end

    test "project editors and viewers cannot toggle MFA requirement", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user: user, role: :admin}]
        )

      ~w(editor viewer)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        {:ok, view, html} =
          live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

        assert html =~ "Project settings"

        toggle_button = element(view, "#toggle-mfa-switch")

        assert render(toggle_button) =~
                 "You do not have permission to perform this action"

        assert render_click(toggle_button) =~
                 "You are not authorized to perform this action."
      end)
    end

    test "only users with MFA enabled can access settings for a project with MFA requirement",
         %{
           conn: conn
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = log_in_user(conn, user)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert html =~ "Project settings"

      ~w(editor viewer admin)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert {:error, {:redirect, %{to: "/mfa_required"}}} =
                 live(
                   conn,
                   ~p"/projects/#{project}/settings",
                   on_error: :raise
                 )
      end)
    end

    test "project admin can toggle support access",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          project_users: [%{user: user, role: :admin}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#collaboration",
          on_error: :raise
        )

      assert html =~ "Project settings"

      assert view
             |> element("#toggle-support-access")
             |> render_click() =~ "Granted access to support users successfully"

      assert %{allow_support_access: true} = Repo.get(Project, project.id)

      assert view
             |> element("#toggle-support-access")
             |> render_click() =~ "Revoked access to support users successfully"

      assert %{allow_support_access: false} = Repo.get(Project, project.id)
    end

    test "project editors and viewers cannot grant support access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user: user, role: :admin}]
        )

      ~w(editor viewer)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        {:ok, view, html} =
          live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

        assert html =~ "Project settings"

        refute has_element?(view, "#toggle-support-access")
      end)
    end

    test "MFA not limited: no banner, button is enabled, and MFA can be toggled",
         %{conn: conn} do
      project = insert(:project)

      project_user =
        insert(:project_user, role: :admin, project: project, user: build(:user))

      stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn _, _ ->
        :ok
      end)

      conn = log_in_user(conn, project_user.user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/settings#security")

      refute has_element?(view, "#toggle-mfa-switch[disabled]")

      assert view
             |> element("#toggle-mfa-switch")
             |> render_click() =~ "Project MFA requirement updated successfully"
    end

    test "MFA limited: banner displayed, button is disabled, and MFA cannot be toggled",
         %{conn: conn} do
      project = insert(:project)

      project_user =
        insert(:project_user, role: :admin, project: project, user: build(:user))

      banner_message = "MFA Feature is disabled"

      stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn %{type: type},
                                                                    _ ->
        component = %Lightning.Extensions.Message{
          attrs: %{text: banner_message},
          function: fn assigns ->
            ~H"""
            {@text}
            """
          end
        }

        case type do
          :require_mfa ->
            {:error, :disabled, component}

          _ ->
            :ok
        end
      end)

      conn = log_in_user(conn, project_user.user)
      {:ok, view, html} = live(conn, ~p"/projects/#{project}/settings#security")

      assert html =~ banner_message
      assert has_element?(view, "#toggle-mfa-switch[disabled]")

      assert view |> render_click("toggle-mfa", %{}) =~
               "You are not authorized to perform this action"
    end
  end

  describe "webhook-security" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "all project users can see the project webhook auth methods" do
      project = insert(:project)
      auth_methods = insert_list(4, :webhook_auth_method, project: project)

      for conn <-
            build_project_user_conns(project, [:editor, :admin, :owner, :viewer]) do
        {:ok, _view, html} =
          live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

        for auth_method <- auth_methods do
          assert html =~ auth_method.name
        end
      end
    end

    test "all project users can see the workflows linked to auth methods" do
      project = insert(:project)
      workflow = insert(:simple_workflow, project: project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          triggers: workflow.triggers
        )

      for conn <-
            build_project_user_conns(project, [:editor, :admin, :owner, :viewer]) do
        {:ok, view, html} =
          live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

        modal_id = "#linked_triggers_for_#{auth_method.id}_modal"

        assert html =~ auth_method.name

        assert has_element?(
                 view,
                 "#display_linked_triggers_link_#{auth_method.id}"
               )

        refute has_element?(view, modal_id)

        view
        |> element("#display_linked_triggers_link_#{auth_method.id}")
        |> render_click()

        assert has_element?(view, modal_id)

        assert view |> element(modal_id) |> render() =~ workflow.name
      end
    end

    test "owners/admins can add a new project webhook auth method, editors/viewers can't" do
      project = insert(:project)

      settings_path =
        ~p"/projects/#{project}/settings"

      modal_id = "webhook_auth_method_modal"

      for conn <- build_project_user_conns(project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            settings_path,
            on_error: :raise
          )

        assert view |> element("button#add_new_auth_method") |> has_element?()

        refute view
               |> element("button#add_new_auth_method:disabled")
               |> has_element?()

        # modal doesn't exist
        refute view |> element("##{modal_id}") |> has_element?()

        # open modal
        html = view |> element("button#add_new_auth_method") |> render_click()
        assert view |> element("##{modal_id}") |> has_element?()

        assert html =~ "Basic HTTP Authentication"
        assert html =~ "API Key Authentication"

        view
        |> form("##{modal_id} form",
          webhook_auth_method: %{auth_type: "basic"}
        )
        |> render_submit() =~ "Create credential"

        # choose form is nolonger shown
        html = render(view)
        refute html =~ "Basic HTTP Authentication"
        refute html =~ "API Key Authentication"

        credential_name = Name.generate()

        refute html =~ credential_name

        view
        |> form("##{modal_id} form",
          webhook_auth_method: %{
            name: credential_name,
            username: "testusername",
            password: "testpassword123"
          }
        )
        |> render_submit()

        assert_patched(view, settings_path)

        # modal doesn't exist
        refute view |> element("##{modal_id}") |> has_element?()

        html = render(view)

        assert html =~ "Webhook auth method created successfully"
        assert html =~ credential_name
      end

      for conn <- build_project_user_conns(project, [:editor, :viewer]) do
        {:ok, view, _html} =
          live(
            conn,
            settings_path,
            on_error: :raise
          )

        assert view
               |> element("button#add_new_auth_method:disabled")
               |> has_element?()

        # forcing the event results in error
        assert render_click(view, "show_modal", %{
                 target: "new_webhook_auth_method"
               }) =~
                 "You are not authorized to perform this action"

        # modal doesn't exist
        refute view |> element("##{modal_id}") |> has_element?()
      end
    end

    test "project viewers cannot add a new project webhook auth method", %{
      conn: conn
    } do
      project = insert(:project)

      project_user =
        insert(:project_user,
          role: :viewer,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert view
             |> element("button#add_new_auth_method:disabled")
             |> has_element?()

      # forcing the event results in error
      assert render_click(view, "show_modal", %{
               target: "new_webhook_auth_method"
             }) =~
               "You are not authorized to perform this action"

      # modal doesn't exist
      refute view |> element("#webhook_auth_method_modal") |> has_element?()
    end

    test "owners/admins can add edit a project webhook auth method, editors/viewers can't" do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic
        )

      settings_path = ~p"/projects/#{project}/settings"

      modal_id = "webhook_auth_method_modal"

      for conn <- build_project_user_conns(project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            settings_path,
            on_error: :raise
          )

        # modal doesn't exist
        refute view |> element("##{modal_id}") |> has_element?()

        assert view
               |> element("a#edit_auth_method_link_#{auth_method.id}")
               |> has_element?()

        view
        |> element("a#edit_auth_method_link_#{auth_method.id}")
        |> render_click()

        # modal exists
        assert view |> element("##{modal_id}") |> has_element?()

        credential_name = Name.generate()

        refute render(view) =~ credential_name

        view
        |> form("##{modal_id} form",
          webhook_auth_method: %{name: credential_name}
        )
        |> render_submit()

        assert_patched(view, settings_path)

        # modal doesn't exist
        refute view |> element("##{modal_id}") |> has_element?()

        html = render(view)
        assert html =~ "Webhook auth method updated successfully"
        assert html =~ credential_name
      end

      for conn <- build_project_user_conns(project, [:editor, :viewer]) do
        {:ok, view, _html} =
          live(
            conn,
            settings_path,
            on_error: :raise
          )

        assert view
               |> element(
                 "a#edit_auth_method_link_#{auth_method.id}.cursor-not-allowed"
               )
               |> has_element?()

        # forcing the event results in error
        assert render_click(view, "show_modal", %{
                 target: "edit_webhook_auth_method",
                 id: auth_method.id
               }) =~
                 "You are not authorized to perform this action"

        # modal doesn't exist
        refute view |> element("##{modal_id}") |> has_element?()
      end
    end

    test "project viewers cannot edit a project webhook auth method", %{
      conn: conn
    } do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic
        )

      project_user =
        insert(:project_user,
          role: :viewer,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert view
             |> element(
               "a#edit_auth_method_link_#{auth_method.id}.cursor-not-allowed"
             )
             |> has_element?()

      # forcing the event results in error
      assert render_click(view, "show_modal", %{
               target: "edit_webhook_auth_method",
               id: auth_method.id
             }) =~
               "You are not authorized to perform this action"

      # modal doesn't exist
      refute view |> element("#webhook_auth_method_modal") |> has_element?()
    end

    test "password is required before displaying the API KEY of a project webhook auth method",
         %{conn: conn} do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :api,
          api_key: "someverystrongapikey1234",
          username: nil,
          password: nil
        )

      project_user =
        insert(:project_user,
          role: :admin,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      view
      |> element("a#edit_auth_method_link_#{auth_method.id}")
      |> render_click()

      modal_id = "webhook_auth_method_modal"

      assert view |> element("##{modal_id}") |> has_element?()

      form_id = "webhook_auth_method"

      assert view |> has_element?("##{form_id}_api_key_action_button", "Show")
      refute view |> has_element?("##{form_id}_api_key_action_button", "Copy")
      # API KEY not in DOM
      refute render(view) =~ auth_method.api_key

      refute view |> has_element?("#reauthentication-form")

      view |> element("##{form_id}_api_key_action_button") |> render_click()

      assert view |> has_element?("#reauthentication-form")

      # test wrong password
      refute render(view) =~ "Invalid! Please try again"

      view
      |> form("#reauthentication-form",
        user: %{password: "wrongpass"}
      )
      |> render_submit()

      assert render(view) =~ "Invalid! Please try again"
      # form still exists
      assert view |> has_element?("#reauthentication-form")

      # correct password
      view
      |> form("#reauthentication-form",
        user: %{password: project_user.user.password}
      )
      |> render_submit()

      refute render(view) =~ "Invalid! Please try again"
      refute view |> has_element?("#reauthentication-form")

      refute view |> has_element?("##{form_id}_api_key_action_button", "Show")
      assert view |> has_element?("##{form_id}_api_key_action_button", "Copy")
      assert render(view) =~ auth_method.api_key
    end

    test "password is required before displaying the password of a project webhook auth method",
         %{conn: conn} do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic,
          api_key: nil,
          username: "testusername",
          password: "someveryverystrongpassword1234"
        )

      project_user =
        insert(:project_user,
          role: :admin,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/settings"
        )

      view
      |> element("a#edit_auth_method_link_#{auth_method.id}")
      |> render_click()

      modal_id = "webhook_auth_method_modal"

      assert view |> element("##{modal_id}") |> has_element?()

      # this is to check that the root tag for the live component is mantained
      root_div = "edit_auth_method_#{auth_method.id}"
      assert has_element?(view, "##{root_div}")

      form_id = "webhook_auth_method"

      assert view |> has_element?("##{form_id}_password_action_button", "Show")
      refute view |> has_element?("##{form_id}_password_action_button", "Copy")
      # password not in DOM
      refute render(view) =~ auth_method.password

      refute view |> has_element?("#reauthentication-form")

      view |> element("##{form_id}_password_action_button") |> render_click()

      assert view |> has_element?("#reauthentication-form")

      # root html tag in livecomponent is mantained
      assert has_element?(view, "##{root_div}")

      # test wrong password
      refute render(view) =~ "Invalid! Please try again"

      view
      |> form("#reauthentication-form",
        user: %{password: "wrongpass"}
      )
      |> render_submit()

      assert render(view) =~ "Invalid! Please try again"
      # form still exists
      assert view |> has_element?("#reauthentication-form")

      # correct password
      view
      |> form("#reauthentication-form",
        user: %{password: project_user.user.password}
      )
      |> render_submit()

      refute render(view) =~ "Invalid! Please try again"
      refute view |> has_element?("#reauthentication-form")

      refute view |> has_element?("##{form_id}_password_action_button", "Show")
      assert view |> has_element?("##{form_id}_password_action_button", "Copy")
      assert render(view) =~ auth_method.password
    end

    test "owners and admins can delete a project webhook auth method",
         %{conn: conn} do
      project = insert(:project)

      for role <- [:owner, :admin] do
        auth_method =
          insert(:webhook_auth_method,
            project: project,
            auth_type: :basic
          )

        project_user =
          insert(:project_user,
            role: role,
            project: project,
            user: build(:user)
          )

        settings_path =
          ~p"/projects/#{project}/settings"

        conn = log_in_user(conn, project_user.user)

        {:ok, view, html} = live(conn, settings_path)

        assert html =~ auth_method.name

        modal_id = "delete_auth_method_#{auth_method.id}_modal"

        refute has_element?(view, "##{modal_id}")

        view
        |> element("a#delete_auth_method_link_#{auth_method.id}")
        |> render_click()

        assert has_element?(view, "##{modal_id}")

        assert view
               |> form("##{modal_id} form",
                 delete_confirmation: %{confirmation: "diel"}
               )
               |> render_change() =~ "Please type DELETE to confirm"

        view
        |> form("##{modal_id} form",
          delete_confirmation: %{confirmation: "DELETE"}
        )
        |> render_submit()

        assert_patched(view, settings_path)

        html = render(view)

        assert html =~ "Your Webhook Authentication method has been deleted."
        refute html =~ auth_method.name
      end

      for role <- [:editor, :viewer] do
        auth_method =
          insert(:webhook_auth_method,
            project: project,
            auth_type: :basic
          )

        project_user =
          insert(:project_user,
            role: role,
            project: project,
            user: build(:user)
          )

        settings_path =
          ~p"/projects/#{project}/settings"

        conn = log_in_user(conn, project_user.user)

        {:ok, view, _html} = live(conn, settings_path)

        modal_id = "delete_auth_method_#{auth_method.id}_modal"

        assert view
               |> has_element?(
                 "a#delete_auth_method_link_#{auth_method.id}.cursor-not-allowed"
               )

        # forcing the event results in error
        assert render_click(view, "show_modal", %{
                 target: "delete_webhook_auth_method",
                 id: auth_method.id
               }) =~
                 "You are not authorized to perform this action"

        # modal doesn't exist
        refute view |> element("##{modal_id}") |> has_element?()
      end
    end
  end

  describe "data-storage" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    @tag role: :owner
    test "project owner can view these settings", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
    end

    @tag role: :admin
    test "project admin can view these settings", %{conn: conn, project: project} do
      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
      assert html =~ "Should OpenFn store input/output data for workflow runs?"

      # retain_all is the default
      assert ["checked"] ==
               view
               |> element("#retain_all")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.attribute("input", "checked")

      # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
      # refute ["checked"] ==
      #          view
      #          |> element("#retain_with_errors")
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.attribute("input", "checked")

      refute ["checked"] ==
               view
               |> element("#erase_all")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.attribute("input", "checked")

      # heads up not shown for retain all
      refute html =~ "heads-up-description"

      # 3 radio buttons descriptions
      assert "Retain input/output data for all workflow runs" =
               view
               |> element(~s{label#[for="retain_all"]})
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.text()
               |> String.trim()

      # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
      # assert "Only retain input/output data when a run fails" =
      #          view
      #          |> element(~s{label#[for="retain_with_errors"]})
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.text()
      #          |> String.trim()

      assert "Never retain input/output data (zero-persistence)" =
               view
               |> element(~s{label#[for="erase_all"]})
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.text()
               |> String.trim()

      # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
      # show heads up for retain_with_errors
      # view
      # |> form("#retention-settings-form",
      #   project: %{
      #     retention_policy: "retain_with_errors"
      #   }
      # )
      # |> render_change()

      # assert ["checked"] ==
      #          view
      #          |> element("#retain_with_errors")
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.attribute("input", "checked")

      # assert "When enabled, you will no longer be able to retry workflow runs as no data will be stored." =
      #          view
      #          |> element("#heads-up-description")
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.find("p")
      #          |> Floki.text()
      #          |> String.trim()

      # show heads up for erase all
      view
      |> form("#retention-settings-form",
        project: %{
          retention_policy: "erase_all"
        }
      )
      |> render_change()

      assert ["checked"] ==
               view
               |> element("#erase_all")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.attribute("input", "checked")

      assert "When enabled, you will no longer be able to retry workflow runs as no data will be stored." =
               view
               |> element("#heads-up-description")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.find("p")
               |> Floki.text()
               |> String.trim()
    end

    @tag role: :editor
    test "project editor does not have permission", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
      assert html =~ "You cannot modify this project&#39;s data storage"

      html =
        render_submit(view, "save_retention_settings", %{
          project: %{
            retention_policy: "retain_all",
            history_retention_period: 14,
            dataclip_retention_period: 7
          }
        })

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :viewer
    test "project viewer does not have permission", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
      assert html =~ "You cannot modify this project&#39;s data storage"

      html =
        render_submit(view, "save_retention_settings", %{
          project: %{
            retention_policy: "retain_all",
            history_retention_period: 14,
            dataclip_retention_period: 7
          }
        })

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :admin
    test "project admin can change the Input/Output Data Storage Policy", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      # save, navigate to other page and saved option is checked when come back
      Enum.reduce(
        # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
        # ["retain_with_errors", "erase_all", "retain_all"],
        ["erase_all", "retain_all"],
        view,
        fn policy, view ->
          view
          |> form("#retention-settings-form",
            project: %{
              retention_policy: policy
            }
          )
          |> render_change()

          assert ["checked"] ==
                   view
                   |> element("#" <> policy)
                   |> render()
                   |> Floki.parse_fragment!()
                   |> Floki.attribute("input", "checked")

          html =
            view
            |> form("#retention-settings-form")
            |> render_submit()

          assert html =~ "Project updated successfully"
          assert html =~ "Input/Output Data Storage Policy"

          assert policy ==
                   project.id
                   |> Projects.get_project!()
                   |> Map.get(:retention_policy)
                   |> Atom.to_string()

          live(conn, ~p"/projects/#{project.id}/w")

          {:ok, view, _html} =
            live(conn, ~p"/projects/#{project.id}/settings#data-storage")

          assert ["checked"] ==
                   view
                   |> element("#" <> policy)
                   |> render()
                   |> Floki.parse_fragment!()
                   |> Floki.attribute("input", "checked")

          view
        end
      )
    end

    @tag role: :admin
    test "history retention period only shows provided options by the extension",
         %{
           conn: conn,
           project: %{id: project_id} = project
         } do
      expected_options = [7, 14]
      other_options = [30, 90, 180, 365]

      expect(
        Lightning.Extensions.MockUsageLimiter,
        :get_data_retention_periods,
        2,
        fn %{project_id: ^project_id} ->
          expected_options
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      html =
        view
        |> element("select[name='project[history_retention_period]']")
        |> render()

      for option <- expected_options do
        assert html =~ "#{option} Days</option>"
      end

      for option <- other_options do
        refute html =~ "#{option} Days</option>"
      end
    end

    @tag role: :admin
    test "history retention period is disabled when only one option is provided",
         %{
           conn: conn,
           project: %{id: project_id} = project
         } do
      expect(
        Lightning.Extensions.MockUsageLimiter,
        :get_data_retention_periods,
        2,
        fn %{project_id: ^project_id} ->
          [7]
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert has_element?(
               view,
               "select[name='project[history_retention_period]']:disabled"
             )
    end

    @tag role: :admin
    test "dataclip retention period is disabled if the history period has not been set",
         %{
           conn: conn,
           project: project
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      # dataclip retention period is disabled if the history period has not been set
      assert is_nil(project.history_retention_period)

      assert has_element?(
               view,
               "select[name='project[dataclip_retention_period]']:disabled"
             )

      view
      |> form("#retention-settings-form",
        project: %{
          history_retention_period: 7
        }
      )
      |> render_change()

      refute has_element?(
               view,
               "select[name='project[dataclip_retention_period]']:disabled"
             )

      assert has_element?(
               view,
               "select[name='project[dataclip_retention_period]']"
             )
    end

    @tag role: :admin
    test "dataclip retention period is disabled if the retention_policy has been set to erase_all",
         %{
           conn: conn,
           project: project
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      selected_dataclip_option =
        element(
          view,
          "select[name='project[dataclip_retention_period]'] option[selected]"
        )

      # nothing has been selected for the dataclip period
      refute has_element?(selected_dataclip_option)

      # let us enable it first by setting the history retention period
      view
      |> form("#retention-settings-form")
      |> render_change(%{
        project: %{
          history_retention_period: 14,
          dataclip_retention_period: 7
        }
      })

      refute has_element?(
               view,
               "#retention-settings-form select[name='project[dataclip_retention_period]']:disabled"
             )

      # 7 Days has been selected for the dataclip period
      assert render(selected_dataclip_option) =~ "7 Days"

      # now let's set the retention policy to erase_all
      view
      |> form("#retention-settings-form",
        project: %{
          retention_policy: "erase_all"
        }
      )
      |> render_change()

      assert has_element?(
               view,
               "#retention-settings-form select[name='project[dataclip_retention_period]']:disabled"
             )

      # 7 days gets cleared. Nothing is now selected
      refute has_element?(selected_dataclip_option)
    end

    @tag role: :admin
    test "project admin can change the retention periods", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      # let's first set the history retention period

      view
      |> form("#retention-settings-form",
        project: %{
          history_retention_period: 7
        }
      )
      |> render_change()

      # trying to set the dataclip retention period more than the history period shows error
      refute render(view) =~
               "must be less or equal to the history retention period"

      html =
        view
        |> form("#retention-settings-form",
          project: %{
            dataclip_retention_period: 14
          }
        )
        |> render_change()

      assert html =~ "must be less or equal to the history retention period"

      # the project gets updated successfully

      html =
        view
        |> form("#retention-settings-form",
          project: %{
            dataclip_retention_period: 7
          }
        )
        |> render_submit()

      assert html =~ "Project updated successfully"
    end

    @tag role: :admin
    test "creates event linked to user when retention period is updated", %{
      conn: conn,
      project: project,
      user: %{id: user_id}
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      view
      |> form("#retention-settings-form",
        project: %{
          history_retention_period: 7
        }
      )
      |> render_submit()

      assert %{actor_id: ^user_id} = Audit |> Repo.one!()
    end

    @tag role: :admin
    test "indicates if there was a failure due to audit creation", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      with_mock(Lightning.Repo, [:passthrough],
        transaction: fn _multi ->
          {:error, :anything_other_than_project, %Ecto.Changeset{}, %{}}
        end
      ) do
        html =
          view
          |> form("#retention-settings-form",
            project: %{
              history_retention_period: 7
            }
          )
          |> render_submit()

        assert html =~ "Changes couldn&#39;t be saved"
      end
    end
  end

  describe "projects settings:collaboration" do
    setup :register_and_log_in_user

    test "only authorized users can access the add collaborators modal", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        button = element(view, "#show_collaborators_modal_button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#add_collaborators_modal")

        # try clicking the button
        assert_raise ArgumentError, ~r/is disabled/, fn ->
          render_click(button)
        end

        # send event either way
        refute render_click(view, "toggle_collaborators_modal") =~
                 "Enter the email address and role of new collaborator"

        # modal is still not present
        refute has_element?(view, "#add_collaborators_modal")
      end

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        button = element(view, "#show_collaborators_modal_button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#add_collaborators_modal")

        # try clicking the button
        assert render_click(button) =~
                 "Enter the email address and role of new collaborator"

        # modal is now present
        assert has_element?(view, "#add_collaborators_modal")
      end
    end

    test "user can add and remove inputs for adding collaborators", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        modal = element(view, "#add_collaborators_modal")

        html = modal |> render() |> Floki.parse_fragment!()

        # we only have 1 email input by default
        assert Floki.find(html, "[type='text'][name$='[email]']") |> Enum.count() ==
                 1

        # we dont have any button to remove the input
        assert Floki.find(html, "button[name$='[collaborators_drop][]']")
               |> Enum.count() == 0

        # lets click to add another row
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_sort" => [0, "new"]})

        html = modal |> render() |> Floki.parse_fragment!()

        # we now have 2 email inputs and 2 buttons to remove the inputs
        assert Floki.find(html, "[type='text'][name$='[email]']") |> Enum.count() ==
                 2

        assert Floki.find(html, "button[name$='[collaborators_drop][]']")
               |> Enum.count() == 2

        # lets click to remove the first row
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_drop" => [0]})

        html = modal |> render() |> Floki.parse_fragment!()

        # we now have 1 email input and we dont have any button to remove the input
        assert Floki.find(html, "[type='text'][name$='[email]']") |> Enum.count() ==
                 1

        assert Floki.find(html, "button[name$='[collaborators_drop][]']")
               |> Enum.count() == 0
      end
    end

    test "adding a non existent user triggers the invite users process", %{
      conn: conn
    } do
      project = insert(:project, name: "my-project")

      {conn, _user} = setup_project_user(conn, project, :owner)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      # Open Modal
      view
      |> element("#show_collaborators_modal_button")
      |> render_click()

      email = "nonexists@localtests.com"

      refute view |> has_element?("#invite_collaborators_modal_form")

      view
      |> form("#add_collaborators_modal_form",
        project: %{
          "collaborators" => %{
            "0" => %{"email" => email, "role" => "editor"}
          }
        }
      )
      |> render_submit()

      assert view |> has_element?("#invite_collaborators_modal_form")

      {:ok, _view, html} =
        view
        |> form("#invite_collaborators_modal_form",
          project: %{
            "invited_collaborators" => %{
              "0" => %{
                "email" => email,
                "role" => "editor",
                "first_name" => "Non",
                "last_name" => "Exists"
              }
            }
          }
        )
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      assert html =~ "Invite sent successfully"

      refute_email_sent(
        to: [{"Non Exists", "nonexists@localtests.com"}],
        subject: "You now have access to \"my-project\""
      )

      assert_email_sent(
        to: [{"Non Exists", "nonexists@localtests.com"}],
        subject: "Join my-project on OpenFn as a collaborator"
      )
    end

    test "inviting an aleady existing user renders an error", %{
      conn: conn
    } do
      project = insert(:project, name: "my-project")

      {conn, user} = setup_project_user(conn, project, :owner)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      # Open Modal
      view
      |> element("#show_collaborators_modal_button")
      |> render_click()

      email = "nonexists@localtests.com"

      refute view |> has_element?("#invite_collaborators_modal_form")

      view
      |> form("#add_collaborators_modal_form",
        project: %{
          "collaborators" => %{
            "0" => %{"email" => email, "role" => "editor"}
          }
        }
      )
      |> render_submit()

      assert view |> has_element?("#invite_collaborators_modal_form")

      assert view
             |> form("#invite_collaborators_modal_form",
               project: %{
                 "invited_collaborators" => %{
                   "0" => %{
                     "email" => user.email,
                     "role" => "editor",
                     "first_name" => "Non",
                     "last_name" => "Exists"
                   }
                 }
               }
             )
             |> render_submit() =~ "This email is already taken"

      refute_email_sent(
        to: [{"", "nonexists@localtests.com"}],
        subject: "You now have access to \"my-project\""
      )

      refute_email_sent(
        to: [{"", "nonexists@localtests.com"}],
        subject: "Join my-project on OpenFn as a collaborator"
      )
    end

    test "adding an existing project user displays an appropriate error message",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        modal = element(view, "#add_collaborators_modal")

        refute render(modal) =~ "This account is already part of this project"

        # lets submit the form

        view
        |> form("#add_collaborators_modal_form",
          project: %{
            "collaborators" => %{
              "0" => %{"email" => user.email, "role" => "editor"}
            }
          }
        )
        |> render_submit()

        assert render(modal) =~ "This account is already part of this project"
      end
    end

    test "adding an owner project user is not allowed",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        modal = element(view, "#add_collaborators_modal")

        refute render(modal) =~ "is invalid"

        # lets submit the form
        view
        |> form("#add_collaborators_modal_form")
        |> render_submit(
          project: %{
            "collaborators" => %{
              "0" => %{"email" => "dummy@email.com", "role" => "owner"}
            }
          }
        )

        assert render(modal) =~ "is invalid"
      end
    end

    test "user can add collaborators successfully",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        [admin, editor, viewer] = insert_list(3, :user)

        # user is not shown in the page
        for new_user <- [admin, editor, viewer] do
          refute html =~ new_user.last_name
        end

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        # lets click to add 2 more rows
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_sort" => [0, "new", "new"]})

        # lets submit the form
        view
        |> form("#add_collaborators_modal_form",
          project: %{
            "collaborators" => %{
              "0" => %{"email" => admin.email, "role" => "admin"},
              "1" => %{"email" => editor.email, "role" => "editor"},
              "2" => %{"email" => viewer.email, "role" => "viewer"}
            }
          }
        )
        |> render_submit()

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project}/settings#collaboration"
          )

        assert flash["info"] =~ "Collaborators added successfully"
      end
    end

    test "add collaborators button is disabled if limit is reached", %{
      conn: conn
    } do
      %{id: project_id} = project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      error_msg = "some meaningful error message"

      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :new_user, amount: 1}, %{project_id: ^project_id} ->
            {:error, :too_many_users, %{text: error_msg}}

          _other_action, _context ->
            :ok
        end
      )

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      assert html =~ error_msg

      assert has_element?(view, "#show_collaborators_modal_button:disabled")
    end

    test "error message is displayed if the allowed limits are exceeded", %{
      conn: conn
    } do
      %{id: project_id} = project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      # users to add
      [admin, editor, viewer] = insert_list(3, :user)

      # return ok for enabling the add collaboratos button
      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :new_user, amount: 1}, %{project_id: ^project_id} ->
            :ok

          _action, _project ->
            :ok
        end
      )

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      # user is not shown in the page
      for new_user <- [admin, editor, viewer] do
        refute html =~ new_user.last_name
      end

      # we only want to allow 3 users. We already 1, the one logged in
      expected_error_msg = "You can only have 3 collaborators in this project"

      # Open Modal
      html =
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

      refute html =~ expected_error_msg,
             "no error message is displayed when the modal is opened"

      # lets click to add 1 more row
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :new_user, amount: 2}, %{project_id: ^project_id} ->
          :ok
        end
      )

      html =
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_sort" => [0, "new"]})

      refute html =~ expected_error_msg,
             "no error message is displayed when only 2 rows are present"

      # lets click to add 1 more row. So we now have 3 rows
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :new_user, amount: 3}, %{project_id: ^project_id} ->
          {:error, :too_many_users, %{text: expected_error_msg}}
        end
      )

      html =
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_sort" => [0, 1, "new"]})

      assert html =~ expected_error_msg,
             "error message is displayed when we more than 2 rows are present"

      # lets click to remove the first row
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :new_user, amount: 2}, %{project_id: ^project_id} ->
          :ok
        end
      )

      html =
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_drop" => [0]})

      refute html =~ expected_error_msg,
             "no error message is displayed when only 2 rows are present"

      # lets submit the form with the 3 users anyway
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :new_user, amount: 3}, %{project_id: ^project_id} ->
          {:error, :too_many_users, %{text: expected_error_msg}}
        end
      )

      html =
        view
        |> form("#add_collaborators_modal_form")
        |> render_submit(
          project: %{
            "collaborators" => %{
              "0" => %{"email" => admin.email, "role" => "admin"},
              "1" => %{"email" => editor.email, "role" => "editor"},
              "2" => %{"email" => viewer.email, "role" => "viewer"}
            }
          }
        )

      assert html =~ expected_error_msg
    end

    test "only authorized users can remove a collaborator", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        project_user =
          insert(:project_user,
            project: project,
            user: build(:user),
            role: :viewer
          )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        tooltip =
          element(view, "#remove_project_user_#{project_user.id}_button-tooltip")

        assert has_element?(tooltip)
        assert render(tooltip) =~ "You do not have permission to remove a user"

        # modal is not present
        refute has_element?(view, "#remove_#{project_user.id}_modal")

        # try sending the event either way
        html =
          render_click(view, "remove_project_user", %{
            "project_user_id" => project_user.id
          })

        assert html =~ "You are not authorized to perform this action"

        # project user still exists
        assert Repo.get(Lightning.Projects.ProjectUser, project_user.id)
      end

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        project_user =
          insert(:project_user,
            project: project,
            user: build(:user),
            role: :viewer
          )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        tooltip =
          element(view, "#remove_project_user_#{project_user.id}_button-tooltip")

        refute has_element?(tooltip)

        # modal is present
        assert has_element?(view, "#remove_#{project_user.id}_modal")

        # try clicking the confirm button
        view
        |> element("#remove_#{project_user.id}_modal_confirm_button")
        |> render_click()

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project}/settings#collaboration"
          )

        assert flash["info"] == "Collaborator removed"

        # project user is removed
        refute Repo.get(Lightning.Projects.ProjectUser, project_user.id)
        # user is not deleted
        assert Repo.get(Lightning.Accounts.User, project_user.user_id)
      end
    end

    test "removing an owner project user is not allowed",
         %{
           conn: conn
         } do
      project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      project_owner =
        insert(:project_user,
          project: project,
          user: build(:user),
          role: :owner
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      tooltip =
        element(view, "#remove_project_user_#{project_owner.id}_button-tooltip")

      assert has_element?(tooltip)
      assert render(tooltip) =~ "You cannot remove an owner"

      # modal is not present
      refute has_element?(view, "#remove_#{project_owner.id}_modal")

      # try sending the event either way
      html =
        render_click(view, "remove_project_user", %{
          "project_user_id" => project_owner.id
        })

      assert html =~ "You are not authorized to perform this action"

      # project user still exists
      assert Repo.get(Lightning.Projects.ProjectUser, project_owner.id)
    end

    test "users cannot remove themselves",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        project_user =
          Repo.get_by(Lightning.Projects.ProjectUser, user_id: user.id)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        tooltip =
          element(view, "#remove_project_user_#{project_user.id}_button-tooltip")

        assert has_element?(tooltip)
        assert render(tooltip) =~ "You cannot remove yourself"

        # modal is not present
        refute has_element?(view, "#remove_#{project_user.id}_modal")

        # try sending the event either way
        html =
          render_click(view, "remove_project_user", %{
            "project_user_id" => project_user.id
          })

        assert html =~ "You are not authorized to perform this action"

        # project user still exists
        assert Repo.get(Lightning.Projects.ProjectUser, project_user.id)
      end
    end

    test "users cant see form to toggle failure alerts if limiter returns error",
         %{conn: conn} do
      %{id: project_id} = project = insert(:project)
      user = insert(:user)

      project_user =
        insert(:project_user, user: user, project: project, failure_alert: true)

      conn = log_in_user(conn, user)

      # let us first return :ok
      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :alert_failure}, %{project_id: ^project_id} ->
            :ok

          _other_action, _context ->
            :ok
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      # form exists
      form_id = "form#failure-alert-#{project_user.id}"
      assert has_element?(view, form_id)

      # status is displayed as enabled
      assert view |> has_element?("#{form_id} option[selected]", "Enabled")

      refute has_element?(view, "#failure-alert-status-#{project_user.id}")

      # now let us return error
      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :alert_failure}, %{project_id: ^project_id} ->
            {:error, :disabled, %{text: "some error message"}}

          _other_action, _context ->
            :ok
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      # form does not exist
      refute has_element?(view, "form#failure-alert-#{project_user.id}")

      # status is displayed as Unavailable even though it is enabled on the project user
      assert view
             |> element("#failure-alert-status-#{project_user.id}")
             |> render() =~ "Unavailable"
    end

    test "removal confirmation modal shows user's credentials that will be removed",
         %{
           conn: conn
         } do
      project = insert(:project)
      {conn, _user} = setup_project_user(conn, project, :admin)

      user_to_remove = insert(:user, first_name: "Amy", last_name: "Admin")

      project_user =
        insert(:project_user,
          project: project,
          user: user_to_remove,
          role: :viewer
        )

      credential =
        insert(:credential,
          name: "DHIS2 play",
          user: user_to_remove,
          project_credentials: [%{project_id: project.id}]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      assert has_element?(view, "#remove_#{project_user.id}_modal")

      modal = element(view, "#remove_#{project_user.id}_modal")
      modal_html = render(modal)

      assert modal_html =~ credential.name
      assert modal_html =~ "and their owned credential #{credential.name}"

      credential2 =
        insert(:credential,
          name: "PostgreSQL",
          user: user_to_remove,
          project_credentials: [%{project_id: project.id}]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collaboration"
        )

      modal = element(view, "#remove_#{project_user.id}_modal")
      modal_html = render(modal)

      assert modal_html =~ "and their owned credentials"
      assert modal_html =~ credential.name
      assert modal_html =~ credential2.name
    end
  end

  describe "project settings:version control" do
    setup :verify_on_exit!

    test "users see appropriate message if version control is not enabled", %{
      conn: conn
    } do
      # Version control is disabled by NOT setting up config
      put_temporary_env(:lightning, :github_app,
        cert: nil,
        app_id: nil,
        app_name: nil,
        client_id: nil,
        client_secret: nil
      )

      project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        {:ok, _view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        assert html =~
                 "Version Control is not configured for this Lightning instance"
      end
    end

    test "authorized users get option to connect their github account if they havent done so",
         %{conn: conn} do
      project = insert(:project)

      # unauthorized users don't get any option at all
      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor]) do
        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        refute html =~ "Connect your OpenFn account to GitHub"
        refute has_element?(view, "#connect-github-link")
      end

      # authorized users
      for {conn, _user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        assert html =~ "Connect your OpenFn account to GitHub"
        assert has_element?(view, "#connect-github-link")
      end
    end

    test "authorized users see form to connect branch if they have already connected their github account",
         %{conn: conn} do
      project = insert(:project)

      # unauthorized users don't see the form at all
      for {conn, user} <-
            setup_project_users(conn, project, [:viewer, :editor]) do
        set_valid_github_oauth_token!(user)

        {:ok, _view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        refute html =~ "Create/update GitHub installations"
      end

      # authorized users
      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        {:ok, _view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        refute html =~ "Connect your OpenFn account to GitHub"
        assert html =~ "Create/update GitHub installations"
      end
    end

    test "users get updated after successfully connecting to github", %{
      conn: conn
    } do
      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: %{"access_token" => "1234567"}}}

        # gets called after successful installation
        %{url: "https://api.github.com/user/installations"}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: %{"installations" => []}}}
      end)

      project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert has_element?(view, "#connect-github-link")
      refute html =~ "Create/update GitHub installations"

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      flash = assert_redirect(view, ~p"/projects/#{project.id}/settings#vcs")

      assert flash["info"] == "Github account linked successfully"

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

      refute has_element?(view, "#connect-github-link")
      assert html =~ "Create/update GitHub installations"
    end

    test "users get updated after failing to connect to github", %{
      conn: conn
    } do
      expected_resp = %{"error" => "something happened"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_resp}}
      end)

      project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert has_element?(view, "#connect-github-link")
      refute html =~ "Create/update GitHub installations"

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      :ok = refute_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

      assert render(view) =~
               "Oops! Github account failed to link. Please try again"

      # button to connect is still available
      assert has_element?(view, "#connect-github-link")
      refute render(view) =~ "Create/update GitHub installations"
    end

    test "github installations get listed properly when an error occurs", %{
      conn: conn
    } do
      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(400, %{"error" => "something terrible"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      # things dont crash
      html = view |> element("#select-installations-input") |> render_async()

      # we only have one option listed
      floki_fragment = Floki.parse_fragment!(html)
      options = Floki.find(floki_fragment, "#select-installations-input li")
      assert Enum.count(options) == 1
      options |> hd() |> Floki.raw_html() =~ "Select an installation"

      # let us try refreshing the installation
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200)

      view |> element("#refresh-installation-button") |> render_click()

      html = view |> element("#select-installations-input") |> render_async()

      # we now have 2 options listed
      floki_fragment = Floki.parse_fragment!(html)

      [installations_input] =
        Floki.find(floki_fragment, "#select-installations-input")

      options = Floki.children(installations_input)
      assert Enum.count(options) == 2
      [default_option, installation_option] = options
      Floki.raw_html(default_option) =~ "Select an installation"

      Floki.raw_html(installation_option) =~
        "#{expected_installation["account"]["type"]}: #{expected_installation["account"]["login"]}"
    end

    test "branches list can be refreshed successfully", %{
      conn: conn
    } do
      expected_installation = %{
        "id" => "1234",
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      expected_branch = %{"name" => "somebranch"}

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [expected_repo]})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      # lets select the installation
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: expected_installation["id"]}
      )

      selected_installation =
        view
        |> element("#select-installations-input")
        |> render_async()
        |> find_selected_option("#select-installations-input li")

      assert selected_installation =~ expected_installation["id"]

      # lets select the repo
      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [expected_branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )

      selected_repo =
        view
        |> element("#select-repos-input")
        |> render_async()
        |> find_selected_option("#select-repos-input li")

      assert selected_repo =~ expected_repo["full_name"]

      # lets select the branch
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"],
          branch: expected_branch["name"]
        }
      )

      selected_branch =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> find_selected_option("#select-branches-input li")

      assert selected_branch =~ expected_branch["name"]

      # deselecting the installation deselects the repo and branch
      view
      |> form("#project-repo-connection-form")
      |> render_change(connection: %{github_installation_id: ""})

      html = render_async(view)

      refute find_selected_option(html, "#select-repos-input li")

      refute find_selected_option(html, "#select-branches-input li")

      # let us list the branches again by following the ritual again
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: expected_installation["id"]}
      )

      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [expected_branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )

      # we should now have 2 options listed for the branches
      # The default and the expected
      options =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> Floki.parse_fragment!()
        |> Floki.find("#select-branches-input li")

      assert Enum.count(options) == 2

      # now let us refresh the branches
      new_branch = %{"name" => "newbranch"}

      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [
        expected_branch,
        new_branch
      ])

      view |> element("#refresh-branches-button") |> render_click()

      # we should now have 3 options listed for the branches
      # The default, the expected and the new branch
      options =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> Floki.parse_fragment!()
        |> Floki.find("#select-branches-input li")

      assert Enum.count(options) == 3
    end

    test "authorized users can save repo connection successfully without setting config path and initiate sync to github immediately",
         %{
           conn: conn
         } do
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      expected_branch = %{"name" => "somebranch"}

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [expected_repo]})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      # we have 2 options listed for installations
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()

      [installations_input] =
        Floki.find(floki_fragment, "#select-installations-input")

      options = Floki.children(installations_input)
      assert Enum.count(options) == 2
      [default_option, installation_option] = options
      Floki.raw_html(default_option) =~ "Select an installation"

      Floki.raw_html(installation_option) =~
        "#{expected_installation["account"]["type"]}: #{expected_installation["account"]["login"]}"

      # before selecting any installation the repos are not listed.
      # We just have the default option
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [repos_input] = Floki.find(floki_fragment, "#select-repos-input")
      options = Floki.children(repos_input)
      assert Enum.count(options) == 1
      options |> hd() |> Floki.raw_html() =~ "Select a repo"

      # lets select the installation
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: expected_installation["id"]}
      )

      # we should now have the repos listed
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [repos_input] = Floki.find(floki_fragment, "#select-repos-input")
      options = Floki.children(repos_input)
      assert Enum.count(options) == 2
      [default_option, repo_option] = options
      Floki.raw_html(default_option) =~ "Select a repo"
      Floki.raw_html(repo_option) =~ expected_repo["full_name"]

      # before selecting any repo, the branches are not listed.
      # We just have the default option

      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [branches_input] = Floki.find(floki_fragment, "#select-branches-input")
      options = Floki.children(branches_input)
      assert Enum.count(options) == 1
      options |> hd() |> Floki.raw_html() =~ "Select a branch"

      # lets select the repo
      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [expected_branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )

      # we should now have the branches listed
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [branches_input] = Floki.find(floki_fragment, "#select-branches-input")
      options = Floki.children(branches_input)
      assert Enum.count(options) == 2
      [default_option, branch_option] = options
      Floki.raw_html(default_option) =~ "Select a branch"
      Floki.raw_html(branch_option) =~ expected_branch["name"]

      # try submitting without selecting branch
      error_msg = "This field can&#39;t be blank"
      refute render(view) =~ error_msg

      html =
        view
        |> form("#project-repo-connection-form")
        |> render_submit()

      assert html =~ error_msg

      # let us submit with the branch

      # push pull.yml
      expect_get_repo(expected_repo["full_name"], 200, expected_repo)
      expect_create_blob(expected_repo["full_name"])

      expect_get_commit(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])

      expect_update_ref(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      # push deploy.yml + config.json
      # deploy.yml blob
      expect_create_blob(expected_repo["full_name"])
      # config.json blob
      expect_create_blob(expected_repo["full_name"])
      expect_get_commit(expected_repo["full_name"], expected_branch["name"])
      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])
      expect_update_ref(expected_repo["full_name"], expected_branch["name"])

      # write secret
      expect_get_public_key(expected_repo["full_name"])
      secret_name = "OPENFN_#{String.replace(project.id, "-", "_")}_API_KEY"
      expect_create_repo_secret(expected_repo["full_name"], secret_name)

      # initialize sync
      expect_create_installation_token(expected_installation["id"])
      expect_get_repo(expected_repo["full_name"], 200, expected_repo)

      expect_create_workflow_dispatch(
        expected_repo["full_name"],
        "openfn-pull.yml"
      )

      view
      |> form("#project-repo-connection-form")
      |> render_submit(
        connection: %{
          branch: expected_branch["name"],
          sync_direction: "pull",
          accept: true
        }
      )

      flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
      assert flash["info"] == "Connection made successfully"
    end

    test "users can save repo connection successfully by setting config path and choosing deploy to lightning immediately",
         %{
           conn: conn
         } do
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      expected_branch = %{"name" => "somebranch"}

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [expected_repo]})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      # lets select the installation
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: expected_installation["id"]}
      )

      # we should now have the repos listed
      render_async(view)

      # lets select the repo
      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [expected_branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )

      # we should now have the branches listed
      render_async(view)

      # let us submit

      # push pull.yml
      expect_get_repo(expected_repo["full_name"], 200, expected_repo)
      expect_create_blob(expected_repo["full_name"])

      expect_get_commit(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])

      expect_update_ref(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      # push deploy.yml
      # only 1 blob is created for the deploy.yml
      expect_create_blob(expected_repo["full_name"])
      expect_get_commit(expected_repo["full_name"], expected_branch["name"])
      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])
      expect_update_ref(expected_repo["full_name"], expected_branch["name"])

      # write secret
      expect_get_public_key(expected_repo["full_name"])
      secret_name = "OPENFN_#{String.replace(project.id, "-", "_")}_API_KEY"
      expect_create_repo_secret(expected_repo["full_name"], secret_name)

      # sync is not initialized

      view
      |> form("#project-repo-connection-form")
      |> render_submit(
        connection: %{
          branch: expected_branch["name"],
          sync_direction: "deploy",
          config_path: "./config.json",
          accept: true
        }
      )

      flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
      assert flash["info"] == "Connection made successfully"
    end

    test "users get an error when saving repo connection if the usage limiter returns an error",
         %{
           conn: conn
         } do
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      expected_branch = %{"name" => "somebranch"}

      %{id: project_id} = project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [expected_repo]})

      Mox.stub_with(
        Lightning.Extensions.MockUsageLimiter,
        Lightning.Extensions.UsageLimiter
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      # lets select the installation
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: expected_installation["id"]}
      )

      # we should now have the repos listed
      render_async(view)

      # lets select the repo
      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [expected_branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )

      # we should now have the branches listed
      render_async(view)

      # let us submit

      error_msg = "Some funny error message"

      Lightning.Extensions.MockUsageLimiter
      |> Mox.expect(:limit_action, fn %{type: :github_sync},
                                      %{project_id: ^project_id} ->
        {:error, :disabled, %{text: error_msg}}
      end)

      view
      |> form("#project-repo-connection-form")
      |> render_submit(
        connection: %{
          branch: expected_branch["name"],
          sync_direction: "pull",
          accept: true
        }
      )

      flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
      assert flash["error"] == error_msg
    end

    test "users get a flash containing the github error in case the api returns an error with error_description key",
         %{
           conn: conn
         } do
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      expected_branch = %{"name" => "somebranch"}

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [expected_repo]})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      # lets select the installation
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: expected_installation["id"]}
      )

      # we should now have the repos listed
      render_async(view)

      # lets select the repo
      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [expected_branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )

      # we should now have the branches listed
      render_async(view)

      # let us submit

      # push pull.yml
      expected_error_msg = "Some error message"

      expect_get_repo(expected_repo["full_name"], 200, expected_repo)

      expect_create_blob(expected_repo["full_name"], 403, %{
        "error_description" => expected_error_msg
      })

      view
      |> form("#project-repo-connection-form")
      |> render_submit(
        connection: %{
          branch: expected_branch["name"],
          sync_direction: "deploy",
          config_path: "./config.json",
          accept: true
        }
      )

      flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
      assert flash["error"] == "Github Error: #{expected_error_msg}"
    end

    test "users get a flash containing the github error in case the api returns an error with message key",
         %{
           conn: conn
         } do
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      expected_branch = %{"name" => "somebranch"}

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [expected_repo]})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      # lets select the installation
      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{github_installation_id: expected_installation["id"]}
      )

      # we should now have the repos listed
      render_async(view)

      # lets select the repo
      expect_create_installation_token(expected_installation["id"])

      expect_get_repo_branches(expected_repo["full_name"], 200, [expected_branch])

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )

      # we should now have the branches listed
      render_async(view)

      # let us submit

      # push pull.yml
      expected_error_msg = "Some error message"

      expect_get_repo(expected_repo["full_name"], 200, expected_repo)

      expect_create_blob(expected_repo["full_name"], 403, %{
        "message" => expected_error_msg
      })

      view
      |> form("#project-repo-connection-form")
      |> render_submit(
        connection: %{
          branch: expected_branch["name"],
          sync_direction: "deploy",
          config_path: "./config.json",
          accept: true
        }
      )

      flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
      assert flash["error"] == "Github Error: #{expected_error_msg}"
    end

    test "connect button is disabled if the usage limiter returns an error",
         %{
           conn: conn
         } do
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      %{id: project_id} = project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

      expect_create_installation_token(expected_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [expected_repo]})

      Mox.stub_with(
        Lightning.Extensions.MockUsageLimiter,
        Lightning.Extensions.UsageLimiter
      )

      error_msg = "Some funny error message"

      Lightning.Extensions.MockUsageLimiter
      |> Mox.stub(:limit_action, fn
        %{type: :github_sync}, %{project_id: ^project_id} ->
          {:error, :disabled,
           %{
             function: fn assigns ->
               ~H"<p>I am an error message that says: {@error}</p>"
             end,
             attrs: %{error: error_msg}
           }}

        _other_action, _context ->
          :ok
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      submit_btn =
        element(
          view,
          "#connect-and-sync-button",
          "Connect Branch & Initiate First Sync"
        )

      assert render(submit_btn) =~ "disabled=\"disabled\""
    end

    @tag :capture_log
    test "all users can see a saved repo connection", %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234"
        )

      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        # we are returning 404 for the access token so that we halt the pipeline for verifying the connection
        expect_create_installation_token(
          repo_connection.github_installation_id,
          404,
          %{"error" => "something terrible"}
        )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#project-repo-connection-form")

        assert html =~ repo_connection.repo
        assert html =~ repo_connection.branch
        assert html =~ repo_connection.github_installation_id
      end
    end

    test "unauthorized users cannot reconnect project even if they have access to the installation",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234"
        )

      expected_installation = %{
        "id" => repo_connection.github_installation_id,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        set_valid_github_oauth_token!(user)

        # NOTE: This hasn't been migrated to the expect_github_action/3 function
        # because of flaky order of expections.
        Mox.expect(Lightning.Tesla.Mock, :call, 5, fn
          # list installations for checking if the user has access to the intallation.
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"installations" => [expected_installation]}
             }}

          # get installation access token. This is called twice.
          # When fetching repos and when verifying connection
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # list repos
          %{url: "https://api.github.com/installation/repositories"}, _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}

          # another call for verifying connection. Probably for checking if a file exists
          # ignoring to halt the pipeline
          %{url: _url}, _opts ->
            {:error, "something unexpected happened"}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        render_async(view)

        refute has_element?(view, "#reconnect-project-button")

        # try sending the event either way
        view
        |> with_target("#github-sync-component")
        |> render_click("reconnect", %{
          "connection" => %{"sync_direction" => "deploy"}
        })

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
        assert flash["error"] == "You are not authorized to perform this action"
      end
    end

    @tag :capture_log
    test "authorized users cannot reconnect project if they don't have access to the installation",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        # list installations for checking if the user has access to the intallation.
        # in this case we return an empty list to simulate user not having access to the installation
        expect_get_user_installations(200, %{"installations" => []})
        # get installation access token. This is called when verifying connection
        expect_create_installation_token(
          repo_connection.github_installation_id,
          404,
          %{"error" => "something bad"}
        )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        render_async(view)

        refute has_element?(view, "#reconnect-project-button")
      end
    end

    test "authorized users can reconnect project if they have access to the installation",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      expected_installation = %{
        "id" => repo_connection.github_installation_id,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => repo_connection.repo,
        "default_branch" => "main"
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 5, fn
          # list installations for checking if the user has access to the intallation.
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"installations" => [expected_installation]}
             }}

          # get installation access token. This is called twice.
          # When fetching repos and when verifying connection
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # list repos
          %{url: "https://api.github.com/installation/repositories"}, _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}

          # another call for verifying connection. Probably for checking if a file exists
          # ignoring to halt the pipeline
          %{url: _url}, _opts ->
            {:error, "something unexpected happened"}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        render_async(view)

        assert has_element?(view, "#reconnect-project-button")

        # let's reconnect
        # push pull.yml
        expect_get_repo(repo_connection.repo, 200, expected_repo)
        expect_create_blob(repo_connection.repo)

        expect_get_commit(
          repo_connection.repo,
          expected_repo["default_branch"]
        )

        expect_create_tree(repo_connection.repo)
        expect_create_commit(repo_connection.repo)

        expect_update_ref(
          repo_connection.repo,
          expected_repo["default_branch"]
        )

        # push deploy.yml + config.json
        # deploy.yml blob
        expect_create_blob(repo_connection.repo)
        # config.json blob
        expect_create_blob(repo_connection.repo)
        expect_get_commit(repo_connection.repo, repo_connection.branch)
        expect_create_tree(repo_connection.repo)
        expect_create_commit(repo_connection.repo)
        expect_update_ref(repo_connection.repo, repo_connection.branch)

        # write secret
        expect_get_public_key(repo_connection.repo)
        secret_name = "OPENFN_#{String.replace(project.id, "-", "_")}_API_KEY"
        expect_create_repo_secret(repo_connection.repo, secret_name)

        # initialize sync
        expect_create_installation_token(repo_connection.github_installation_id)
        expect_get_repo(repo_connection.repo, 200, expected_repo)

        expect_create_workflow_dispatch(
          repo_connection.repo,
          "openfn-pull.yml"
        )

        view
        |> form("#reconnect-project-form")
        |> render_submit(
          connection: %{"sync_direction" => "pull", "accept" => "true"}
        )

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Connected to GitHub"
      end
    end

    test "authorized users get an error when reconnecting if the usage limiter returns an error",
         %{conn: conn} do
      %{id: project_id} = project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      expected_installation = %{
        "id" => repo_connection.github_installation_id,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 5, fn
          # list installations for checking if the user has access to the intallation.
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"installations" => [expected_installation]}
             }}

          # get installation access token. This is called twice.
          # When fetching repos and when verifying connection
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # list repos
          %{url: "https://api.github.com/installation/repositories"}, _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}

          # another call for verifying connection. Probably for checking if a file exists
          # ignoring to halt the pipeline
          %{url: _url}, _opts ->
            {:error, "something unexpected happened"}
        end)

        Mox.stub_with(
          Lightning.Extensions.MockUsageLimiter,
          Lightning.Extensions.UsageLimiter
        )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        render_async(view)

        assert has_element?(view, "#reconnect-project-button")

        # let's reconnect
        error_msg = "Some funny error message"

        Lightning.Extensions.MockUsageLimiter
        |> Mox.expect(:limit_action, fn %{type: :github_sync},
                                        %{project_id: ^project_id} ->
          {:error, :disabled, %{text: error_msg}}
        end)

        view
        |> form("#reconnect-project-form")
        |> render_submit(
          connection: %{"sync_direction" => "pull", "accept" => "true"}
        )

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["error"] == error_msg
      end
    end

    test "reconnect button does not show if everything checks out",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      for {conn, user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        set_valid_github_oauth_token!(user)

        repo_name = repo_connection.repo
        branch_name = repo_connection.branch
        installation_id = repo_connection.github_installation_id

        expected_default_branch = "main"

        expected_deploy_yml_path =
          ".github/workflows/openfn-#{repo_connection.project_id}-deploy.yml"

        expected_config_json_path =
          "openfn-#{repo_connection.project_id}-config.json"

        expected_secret_name =
          "OPENFN_#{String.replace(repo_connection.project_id, "-", "_")}_API_KEY"

        Mox.expect(Lightning.Tesla.Mock, :call, 9, fn
          # list installations for checking if the user has access to the installation.
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "installations" => [
                   %{
                     "id" => installation_id,
                     "account" => %{
                       "type" => "User",
                       "login" => "username"
                     }
                   }
                 ]
               }
             }}

          # get installation access token. This is called twice.
          # When fetching repos and when verifying connection
          %{
            url:
              "https://api.github.com/app/installations/" <>
                  ^installation_id <> "/access_tokens"
          },
          _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # list repos. This goes hand in hand installations
          %{url: "https://api.github.com/installation/repositories"}, _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}

          # get repo content
          %{url: "https://api.github.com/repos/" <> ^repo_name}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"default_branch" => expected_default_branch}
             }}

          # check if pull yml exists in the default branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^expected_default_branch}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/openfn-pull.yml"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if deploy yml exists in the target branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^branch_name}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/" <> ^expected_deploy_yml_path
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if config.json exists in the target branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^branch_name}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/" <> ^expected_config_json_path
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if api key secret exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/actions/secrets/" <> ^expected_secret_name
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{}}}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#reconnect-project-button")

        assert html =~ "Your repository is properly configured."
      end
    end

    @tag :capture_log
    test "unauthorized users cannot remove github connection", %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      for {conn, user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        # giving the user a valid token
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # list installations for checking if the user has access to the installation.
          # we return 400 to halt the pipeline
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 400,
               body: %{"something" => "bad"}
             }}

          # get access token. Gets called when verifying connection
          %{
            url: "https://api.github.com/app/installations/" <> _installation_id
          },
          _opts ->
            {:ok,
             %Tesla.Env{
               status: 404,
               body: %{"something" => "not right"}
             }}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#remove_connection_modal")

        refute html =~ "Remove Integration"

        # try sending the delete event either way
        view
        |> with_target("#github-sync-component")
        |> render_click("delete-connection", %{})

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
        assert flash["error"] == "You are not authorized to perform this action"

        assert Lightning.Repo.reload(repo_connection)
      end
    end

    @tag :capture_log
    test "authorized users who have not setup github accounts can remove github connection",
         %{conn: conn} do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        repo_connection =
          insert(:project_repo_connection,
            project: project,
            repo: "someaccount/somerepo",
            branch: "somebranch",
            github_installation_id: "1234",
            access_token: "someaccesstoken"
          )

        assert is_nil(user.github_oauth_token)

        Mox.expect(Lightning.Tesla.Mock, :call, 1, fn
          # get access token. Gets called when verifying connection
          # we return 400 to halt the pipeline
          %{
            url: "https://api.github.com/app/installations/" <> _installation_id
          },
          _opts ->
            {:ok,
             %Tesla.Env{
               status: 404,
               body: %{"something" => "not right"}
             }}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        assert has_element?(view, "#remove_connection_modal")
        assert has_element?(view, "#remove_connection_modal_confirm_button")
        assert html =~ "Remove Integration"

        # click the confirm button
        view
        |> element("#remove_connection_modal_confirm_button")
        |> render_click()

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Connection removed successfully"

        refute Lightning.Repo.reload(repo_connection)
      end
    end

    @tag :capture_log
    test "authorized users with valid github oauth can remove github connection even when undoing some github actions fail",
         %{conn: conn} do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        user = set_valid_github_oauth_token!(user)

        repo_connection =
          insert(:project_repo_connection,
            project: project,
            repo: "someaccount/somerepo",
            branch: "somebranch",
            github_installation_id: "1234",
            access_token: "someaccesstoken"
          )

        assert is_map(user.github_oauth_token)

        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # get access token. Gets called when verifying connection
          # we return 400 to halt the pipeline
          %{url: "https://api.github.com/app/installations/" <> _rest}, _opts ->
            {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}

          # check if user has access to the installation
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        assert has_element?(view, "#remove_connection_modal")
        assert has_element?(view, "#remove_connection_modal_confirm_button")
        assert html =~ "Remove Integration"

        # check if deploy yml exists for deletion
        expected_deploy_yml_path =
          ".github/workflows/openfn-#{project.id}-deploy.yml"

        expect_get_repo_content(repo_connection.repo, expected_deploy_yml_path)

        # deletes successfully
        expect_delete_repo_content(
          repo_connection.repo,
          expected_deploy_yml_path
        )

        # check if deploy yml exists for deletion
        expected_config_json_path = "openfn-#{project.id}-config.json"
        expect_get_repo_content(repo_connection.repo, expected_config_json_path)
        # fails to delete
        expect_delete_repo_content(
          repo_connection.repo,
          expected_config_json_path,
          400,
          %{"something" => "happened"}
        )

        # delete secret
        expect_delete_repo_secret(
          repo_connection.repo,
          "OPENFN_#{String.replace(project.id, "-", "_")}_API_KEY"
        )

        # click the confirm button
        view
        |> element("#remove_connection_modal_confirm_button")
        |> render_click()

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Connection removed successfully"

        refute Lightning.Repo.reload(repo_connection)
      end
    end

    @tag :capture_log
    test "unauthorized users cannot initiate github sync", %{conn: conn} do
      project = insert(:project)

      insert(:project_repo_connection,
        project: project,
        repo: "someaccount/somerepo",
        branch: "somebranch",
        github_installation_id: "1234",
        access_token: "someaccesstoken"
      )

      for {conn, user} <- setup_project_users(conn, project, [:viewer]) do
        # giving the user a valid token
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # list installations for checking if the user has access to the installation.
          # we return 400 to halt the pipeline
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok, %Tesla.Env{status: 400, body: %{"something" => "bad"}}}

          # get access token. Gets called when verifying connection
          %{url: "https://api.github.com/app/installations/" <> _rest}, _opts ->
            {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}
        end)

        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

        html = render_async(view)

        assert html =~ "Contact an editor or admin to sync."
        assert has_element?(view, "#initiate-sync-button:disabled")

        # try sending the sync event either way
        view
        |> with_target("#github-sync-component")
        |> render_click("initiate-sync", %{})

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
        assert flash["error"] == "You are not authorized to perform this action"
      end
    end

    test "authorized users can initiate github sync successfully", %{
      conn: conn
    } do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      for {conn, user} <-
            setup_project_users(conn, project, [:editor, :admin, :owner]) do
        # users dont need the oauth token in order to initialize sync
        assert is_nil(user.github_oauth_token)

        # ensure project is all setup
        repo_name = repo_connection.repo
        branch_name = repo_connection.branch
        installation_id = repo_connection.github_installation_id

        expected_default_branch = "main"

        expected_deploy_yml_path =
          ".github/workflows/openfn-#{repo_connection.project_id}-deploy.yml"

        expected_config_json_path =
          "openfn-#{repo_connection.project_id}-config.json"

        expected_secret_name =
          "OPENFN_#{String.replace(repo_connection.project_id, "-", "_")}_API_KEY"

        Mox.expect(Lightning.Tesla.Mock, :call, 6, fn
          # get installation access token.
          # called when verifying connection
          %{
            url:
              "https://api.github.com/app/installations/" <>
                  ^installation_id <> "/access_tokens"
          },
          _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # get repo content
          %{url: "https://api.github.com/repos/" <> ^repo_name}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"default_branch" => expected_default_branch}
             }}

          # check if pull yml exists in the default branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^expected_default_branch}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/openfn-pull.yml"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if deploy yml exists in the target branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^branch_name}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/" <> ^expected_deploy_yml_path
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if config.json exists in the target branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^branch_name}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/" <> ^expected_config_json_path
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if api key secret exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/actions/secrets/" <> ^expected_secret_name
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{}}}
        end)

        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

        html = render_async(view)

        refute html =~ "Contact an editor or admin to sync."

        button = element(view, "#initiate-sync-button")
        assert has_element?(button)

        # try clicking the button
        expect_create_installation_token(repo_connection.github_installation_id)
        expect_get_repo(repo_connection.repo)
        expect_create_workflow_dispatch(repo_connection.repo, "openfn-pull.yml")

        render_click(button)

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Github sync initiated"
      end
    end

    test "authorized users get an error when initiating github sync if the usage limiter returns an error",
         %{
           conn: conn
         } do
      %{id: project_id} = project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      Mox.stub_with(
        Lightning.Extensions.MockUsageLimiter,
        Lightning.Extensions.UsageLimiter
      )

      error_msg = "Some funny error message"

      Lightning.Extensions.MockUsageLimiter
      |> Mox.stub(:limit_action, fn
        %{type: :github_sync}, %{project_id: ^project_id} ->
          {:error, :disabled,
           %{
             function: fn assigns ->
               ~H"<p>I am an error message that says: {@error}</p>"
             end,
             attrs: %{error: error_msg}
           }}

        _other_action, _context ->
          :ok
      end)

      for {conn, _user} <-
            setup_project_users(conn, project, [:editor, :admin, :owner]) do
        # ensure project is all setup
        repo_name = repo_connection.repo
        branch_name = repo_connection.branch
        installation_id = repo_connection.github_installation_id

        expected_default_branch = "main"

        expected_deploy_yml_path =
          ".github/workflows/openfn-#{repo_connection.project_id}-deploy.yml"

        expected_config_json_path =
          "openfn-#{repo_connection.project_id}-config.json"

        expected_secret_name =
          "OPENFN_#{String.replace(repo_connection.project_id, "-", "_")}_API_KEY"

        Mox.expect(Lightning.Tesla.Mock, :call, 6, fn
          # get installation access token.
          # called when verifying connection
          %{
            url:
              "https://api.github.com/app/installations/" <>
                  ^installation_id <> "/access_tokens"
          },
          _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # get repo content
          %{url: "https://api.github.com/repos/" <> ^repo_name}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"default_branch" => expected_default_branch}
             }}

          # check if pull yml exists in the default branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^expected_default_branch}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/openfn-pull.yml"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if deploy yml exists in the target branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^branch_name}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/" <> ^expected_deploy_yml_path
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if config.json exists in the target branch
          %{
            method: :get,
            query: [{:ref, "heads/" <> ^branch_name}],
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/" <> ^expected_config_json_path
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if api key secret exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/actions/secrets/" <> ^expected_secret_name
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{}}}
        end)

        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

        html = render_async(view)

        refute html =~ "Contact an editor or admin to sync."

        button = element(view, "#initiate-sync-button")
        assert has_element?(button)

        assert render(button) =~ "disabled=\"disabled\""
      end
    end

    test "error banner is displayed if github sync usage limiter returns an error",
         %{
           conn: conn
         } do
      %{id: project_id} = project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        error_msg = "I am a robot"

        Lightning.Extensions.MockUsageLimiter
        |> Mox.stub(:check_limits, fn %{project_id: ^project_id} -> :ok end)
        |> Mox.stub(:limit_action, fn
          %{type: :github_sync}, %{project_id: ^project_id} ->
            {:error, :disabled,
             %{
               function: fn assigns ->
                 ~H"<p>I am an error message that says: {@error}</p>"
               end,
               attrs: %{error: error_msg}
             }}

          _other_action, _context ->
            :ok
        end)

        {:ok, _view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        assert html =~ error_msg
      end
    end
  end

  describe "project settings:collections" do
    setup :register_and_log_in_user

    test "only authorized users can access the create modal", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collections"
          )

        button = element(view, "#open-create-collection-modal-button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#create-collection-modal")

        # try clicking the button
        assert_raise ArgumentError, ~r/is disabled/, fn ->
          render_click(button)
        end

        # send event either way
        view
        |> with_target("#collections")
        |> render_click("toggle_action", %{"action" => "new"})

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project.id}/settings#collections"
          )

        assert flash["error"] == "You are not authorized to perform this action"
      end

      for {conn, _user} <-
            setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collections"
          )

        button = element(view, "#open-create-collection-modal-button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#create-collection-modal")

        # try clicking the button
        render_click(button)

        # modal is now present
        assert has_element?(view, "#create-collection-modal")

        # clicking close button closes the modal
        view
        |> element("#create-collection-modal button", "Cancel")
        |> render_click()

        # modal is now closed
        refute has_element?(view, "#create-collection-modal")
      end
    end

    test "user can create collection successfully", %{
      conn: conn
    } do
      project = insert(:project)

      for {{conn, _user}, index} <-
            setup_project_users(conn, project, [:owner, :admin])
            |> Enum.with_index() do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collections"
          )

        # open the modal
        view |> element("#open-create-collection-modal-button") |> render_click()

        # modal is now present
        assert has_element?(view, "#create-collection-modal")

        # fill in the form
        collection_name = "test collection #{index}"
        expected_collection_name = String.replace(collection_name, " ", "-")

        html =
          view
          |> form("#create-collection-modal form",
            collection: %{raw_name: collection_name}
          )
          |> render_change()

        assert html =~ "Your collection will be named"

        # collection does not exist
        refute Lightning.Repo.get_by(Lightning.Collections.Collection,
                 project_id: project.id,
                 name: expected_collection_name
               )

        # submit the form
        view |> form("#create-collection-modal form") |> render_submit()

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project.id}/settings#collections"
          )

        assert flash["info"] == "Collection created"

        # collection now exists
        assert Lightning.Repo.get_by(Lightning.Collections.Collection,
                 project_id: project.id,
                 name: expected_collection_name
               )
      end
    end

    test "choosing an already taken name shows an error", %{
      conn: conn,
      user: user
    } do
      project = insert(:project)
      collection = insert(:collection, project: project)

      conn = setup_project_user(conn, project, user, :owner)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collections"
        )

      # open the modal
      view |> element("#open-create-collection-modal-button") |> render_click()

      # modal is now present
      assert has_element?(view, "#create-collection-modal")

      # fill in the form and submit with the same name
      view
      |> form("#create-collection-modal form",
        collection: %{raw_name: collection.name}
      )
      |> render_change()

      html =
        view
        |> form("#create-collection-modal form")
        |> render_submit()

      assert html =~ "A collection with this name already exists"
    end

    test "shows an error when the limiter returns an error", %{
      conn: conn,
      user: user
    } do
      project = insert(:project)

      conn = setup_project_user(conn, project, user, :owner)

      error_msg = "Some error message"

      Mox.stub(Lightning.Extensions.MockCollectionHook, :handle_create, fn
        _attrs ->
          {:error, :exceeds_limit, %{text: error_msg}}
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#collections"
        )

      # open the modal
      view |> element("#open-create-collection-modal-button") |> render_click()

      # modal is now present
      assert has_element?(view, "#create-collection-modal")

      # fill in the form and submit with the same name
      view
      |> form("#create-collection-modal form",
        collection: %{raw_name: "some name"}
      )
      |> render_change()

      view
      |> form("#create-collection-modal form")
      |> render_submit()

      flash =
        assert_redirected(
          view,
          ~p"/projects/#{project.id}/settings#collections"
        )

      assert flash["error"] == error_msg
    end

    test "unauthorized users cannot edit a collection", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        collection = insert(:collection, project: project)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collections"
          )

        button = element(view, "#edit-collection-#{collection.id}-button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#edit-collection-#{collection.id}-modal")

        # try clicking the button
        assert_raise ArgumentError, ~r/is disabled/, fn ->
          render_click(button)
        end

        # send event either way
        view
        |> with_target("#collections")
        |> render_click("toggle_action", %{
          "action" => "edit",
          "collection" => collection.name
        })

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project.id}/settings#collections"
          )

        assert flash["error"] == "You are not authorized to perform this action"
      end
    end

    test "authorized users can edit a collection successfully", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:owner, :admin]) do
        collection = insert(:collection, project: project)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collections"
          )

        # open the modal
        view
        |> element("#edit-collection-#{collection.id}-button")
        |> render_click()

        # modal is now present
        assert has_element?(view, "#edit-collection-#{collection.id}-modal")

        # fill in the form
        new_collection_name = "#{collection.name}-#{collection.id}"

        html =
          view
          |> form("#edit-collection-#{collection.id}-modal form",
            collection: %{raw_name: new_collection_name}
          )
          |> render_change()

        assert html =~ "Your collection will be named"

        # collection does not exist
        refute Lightning.Repo.get_by(Lightning.Collections.Collection,
                 project_id: project.id,
                 name: new_collection_name
               )

        # submit the form
        view
        |> form("#edit-collection-#{collection.id}-modal form")
        |> render_submit()

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project.id}/settings#collections"
          )

        assert flash["info"] == "Collection updated"

        assert Lightning.Repo.get_by(Lightning.Collections.Collection,
                 project_id: project.id,
                 name: new_collection_name
               )
      end
    end

    test "unauthorized users cannot delete a collection", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        collection = insert(:collection, project: project)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collections"
          )

        button = element(view, "#delete-collection-#{collection.id}-button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#delete-collection-#{collection.id}-modal")

        # try clicking the button
        assert_raise ArgumentError, ~r/is disabled/, fn ->
          render_click(button)
        end

        # send event either way
        view
        |> with_target("#collections")
        |> render_click("toggle_action", %{
          "action" => "delete",
          "collection" => collection.name
        })

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project.id}/settings#collections"
          )

        assert flash["error"] == "You are not authorized to perform this action"
      end
    end

    test "authorized users can delete a collection successfully", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:owner, :admin]) do
        collection = insert(:collection, project: project)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collections"
          )

        # open the modal
        view
        |> element("#delete-collection-#{collection.id}-button")
        |> render_click()

        # modal is now present
        assert has_element?(view, "#delete-collection-#{collection.id}-modal")

        # click the delete button
        view
        |> element("#delete-collection-#{collection.id}-modal_confirm_button")
        |> render_click()

        flash =
          assert_redirected(
            view,
            ~p"/projects/#{project.id}/settings#collections"
          )

        assert flash["info"] == "Collection deleted"

        # collection does not exist
        refute Lightning.Repo.get(
                 Lightning.Collections.Collection,
                 collection.id
               )
      end
    end
  end

  defp find_selected_option(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Enum.map(&Floki.raw_html/1)
    |> Enum.find(fn el -> el =~ "selected=\"true\"" end)
  end

  defp find_user_index_in_list(view, user) do
    Floki.parse_fragment!(render(view))
    |> Floki.find("#project-form tbody tr")
    |> Enum.find_index(fn el ->
      el
      |> Floki.find("td:first-child()")
      |> Floki.text() =~
        "#{user.first_name} #{user.last_name}"
    end)
    |> to_string()
  end

  # Helper to check element order in rendered HTML using proper parsing
  defp assert_elements_in_order(
         html,
         elements,
         table_selector \\ "table tbody tr"
       ) do
    parsed_html = Floki.parse_fragment!(html)
    rows = Floki.find(parsed_html, table_selector)

    row_texts = Enum.map(rows, fn row -> Floki.text(row) end)

    # Find positions of each element in the row texts
    positions =
      Enum.map(elements, fn element ->
        Enum.find_index(row_texts, fn row_text ->
          String.contains?(row_text, element)
        end)
      end)

    # Check if positions are in ascending order
    positions == Enum.sort(positions)
  end

  defp get_element_order(html, elements, table_selector \\ "table tbody tr") do
    parsed_html = Floki.parse_fragment!(html)
    rows = Floki.find(parsed_html, table_selector)

    row_texts = Enum.map(rows, fn row -> Floki.text(row) end)

    # Find positions of each element in the row texts
    Enum.map(elements, fn element ->
      Enum.find_index(row_texts, fn row_text ->
        String.contains?(row_text, element)
      end)
    end)
  end
end
