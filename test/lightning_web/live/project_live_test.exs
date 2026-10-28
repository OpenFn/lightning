defmodule LightningWeb.ProjectLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Phoenix.Component
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.AdaptorTestHelpers
  import Lightning.Factories
  import LightningWeb.ProjectSettingsPageHelpers

  import LightningWeb.CredentialPageHelpers, only: [raw_values: 1]

  import Lightning.ApplicationHelpers,
    only: [put_temporary_env: 3]

  import Lightning.GithubHelpers
  import Swoosh.TestAssertions

  import Mock
  import Mox

  alias Lightning.Auditing.Audit
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias LightningWeb.ProjectLive.Settings

  setup :stub_usage_limiter_ok
  setup :verify_on_exit!

  # The admin projects page is drawn by React from data-props. Sorting and
  # filtering the list and the member rows, the owner messages, the disabled
  # Save and the dialog's name check are tested in the design system's
  # AdminProjectsPage.test.tsx; the events the island sends in
  # assets/test/design-system/AdminProjectsPage.test.tsx. These tests cover
  # the gates and what the server sends and does.
  @admin_page "#admin-projects-page"

  defp admin_props(view), do: page_props(view, @admin_page)

  defp admin_rows(view), do: admin_props(view)["projects"]

  defp save_project(view, raw_name, roles),
    do:
      push_page_event(view, @admin_page, "save_project", %{
        "rawName" => raw_name,
        "roles" => roles
      })

  defp delete_project(view, name),
    do:
      push_page_event(view, @admin_page, "delete_project", %{
        "nameConfirmation" => name
      })

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the index page", %{conn: conn} do
      {:ok, conn} =
        live(conn, ~p"/settings/projects") |> follow_redirect(conn, "/projects")

      assert conn.resp_body =~ "Sorry, you don&#39;t have access to that."
    end

    test "cannot access the new page", %{conn: conn} do
      {:ok, conn} =
        live(conn, ~p"/settings/projects/new")
        |> follow_redirect(conn, "/projects")

      assert conn.resp_body =~ "Sorry, you don&#39;t have access to that."
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

    test "lists all projects", %{conn: conn, project: project, user: superuser} do
      owner = insert(:user, first_name: "John", last_name: "Owner")
      insert(:project_user, project: project, user: owner, role: :owner)

      {:ok, view, html} = live(conn, ~p"/settings/projects")

      assert html =~ "Projects"

      assert %{
               "name" => name,
               "description" => _,
               "insertedAt" => inserted_at,
               "ownerName" => "John Owner",
               "scheduledDeletion" => nil
             } = Enum.find(admin_rows(view), &(&1["id"] == project.id))

      assert name == project.name
      assert String.ends_with?(inserted_at, "Z")
      assert admin_props(view)["form"] == nil
      assert admin_props(view)["deleteProject"] == nil

      # The form routes send the users, not the list.
      {:ok, view, _html} = live(conn, ~p"/settings/projects/new")
      assert admin_rows(view) == []

      assert superuser.id in Enum.map(
               admin_props(view)["form"]["users"],
               & &1["id"]
             )
    end

    test "fails to save a project with no members", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/projects/new")

      assert %{"form" => %{"project" => nil, "users" => users}} =
               admin_props(view)

      assert Enum.all?(users, &Map.has_key?(&1, "email"))

      save_project(view, "some name", %{})

      assert_reply(view, %{
        fieldErrors: %{
          "owner" => [
            "Every project must have exactly one owner. Please specify one below."
          ]
        }
      })

      refute Repo.get_by(Project, name: "some-name")
    end

    test "saves new project with members", %{conn: conn, user: superuser} do
      user_1 = insert(:user, first_name: "1st", last_name: "user")
      user_2 = insert(:user, first_name: "another", last_name: "person")

      {:ok, view, _html} = live(conn, ~p"/settings/projects/new")

      save_project(view, "some name", %{
        user_1.id => "owner",
        user_2.id => "owner"
      })

      assert_reply(view, %{
        fieldErrors: %{"owner" => ["A project can have only one owner."]}
      })

      save_project(view, "", %{user_1.id => "owner"})
      assert_reply(view, %{fieldErrors: %{"rawName" => [blank]}})
      assert blank =~ "can't be blank"

      save_project(view, "some name", %{
        user_1.id => "owner",
        user_2.id => "editor",
        # Unknown users are ignored; the superuser is listed but gets no role.
        Ecto.UUID.generate() => "owner",
        superuser.id => ""
      })

      assert_ok(view)
      assert_patch(view, ~p"/settings/projects")
      assert render(view) =~ "Project created successfully"

      project =
        Repo.get_by!(Project, name: "some-name") |> Repo.preload(:project_users)

      assert project.project_users
             |> Enum.map(&{&1.user_id, &1.role})
             |> Enum.sort() ==
               Enum.sort([{user_1.id, :owner}, {user_2.id, :editor}])

      assert_email_sent(
        to: [Swoosh.Email.Recipient.format(user_1)],
        subject: "You now have access to \"some-name\""
      )

      assert_email_sent(
        to: [Swoosh.Email.Recipient.format(user_2)],
        subject: "You now have access to \"some-name\""
      )
    end

    test "allows a superuser to schedule projects for deletion in the projects list",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}/delete")

      assert admin_props(view)["deleteProject"] == %{
               "id" => project.id,
               "name" => project.name
             }

      assert admin_props(view)["gracePeriodDays"] >= 0

      delete_project(view, "invalid name")
      assert_reply(view, %{error: "doesn't match the project name"})
      refute Repo.reload!(project).scheduled_deletion

      {:ok, _view, html} =
        view
        |> delete_project(project.name)
        |> follow_redirect(conn, ~p"/settings/projects")

      assert html =~ "Project scheduled for deletion"
      assert Repo.reload!(project).scheduled_deletion
    end

    test "refuses to act when the project's deletion changed since the dialog opened",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}/delete")

      project
      |> Ecto.Changeset.change(%{scheduled_deletion: ~U[2030-01-01 00:00:00Z]})
      |> Repo.update!()

      delete_project(view, project.name)

      assert_reply(view, %{
        error:
          "This project's deletion changed since the dialog opened. Reload the page."
      })

      assert Repo.get(Project, project.id)
    end

    test "refuses a delete when no dialog is open, and payloads that are not maps",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/settings/projects")

      delete_project(view, project.name)
      assert_reply(view, %{error: "Project not found"})

      for event <- ["cancel_deletion", "delete_project", "save_project"] do
        push_page_event(view, @admin_page, event, ["x"])
        assert_reply(view, %{error: "Invalid request"})
      end

      refute Repo.reload!(project).scheduled_deletion
    end

    test "sends the list back when the project to delete does not exist", %{
      conn: conn
    } do
      # A patch during mount is a redirect to the test; the flash rides along.
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert {:error,
                {:live_redirect, %{to: "/settings/projects", flash: flash}}} =
                 live(conn, "/settings/projects/#{id}/delete")

        assert flash["error"] == "Project not found"
      end
    end

    test "allows a superuser to cancel scheduled deletion on a project", %{
      conn: conn
    } do
      project =
        project_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, view, _html} = live(conn, ~p"/settings/projects", on_error: :raise)

      assert %{"scheduledDeletion" => scheduled} =
               Enum.find(admin_rows(view), &(&1["id"] == project.id))

      assert scheduled

      push_page_event(view, @admin_page, "cancel_deletion", %{"id" => project.id})

      assert_ok(view)
      assert_patch(view, ~p"/settings/projects")
      assert render(view) =~ "Project deletion canceled"

      assert %{"scheduledDeletion" => nil} =
               Enum.find(admin_rows(view), &(&1["id"] == project.id))

      refute Repo.reload!(project).scheduled_deletion

      for id <- [Ecto.UUID.generate(), "not-a-uuid", nil] do
        push_page_event(view, @admin_page, "cancel_deletion", %{"id" => id})
        assert_reply(view, %{error: "Project not found"})
      end

      # Only a scheduled project has a deletion to cancel.
      push_page_event(view, @admin_page, "cancel_deletion", %{"id" => project.id})

      assert_reply(view, %{error: "Invalid request"})
    end

    test "allows a superuser to perform delete now action on a scheduled for deletion project",
         %{conn: conn} do
      project =
        project_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}/delete", on_error: :raise)

      {:ok, _view, html} =
        view
        |> delete_project(project.name)
        |> follow_redirect(conn, ~p"/settings/projects")

      assert html =~
               "Project deletion started. This may take a while to complete."
    end

    test "Edits a project", %{conn: conn, user: superuser} do
      user1 = insert(:user, first_name: "Alice", last_name: "Owner")
      user2 = insert(:user, first_name: "Bob", last_name: "Viewer")

      project =
        insert(:project, project_users: [%{role: :owner, user_id: user1.id}])

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      assert %{
               "form" => %{
                 "project" => %{"id" => id, "name" => name, "members" => members},
                 "users" => users
               }
             } = admin_props(view)

      assert id == project.id
      assert name == project.name
      assert members == [%{"userId" => user1.id, "role" => "owner"}]
      assert user2.id in Enum.map(users, & &1["id"])

      save_project(view, project.name, %{
        user1.id => "owner",
        user2.id => "viewer"
      })

      assert_ok(view)
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

    test "editing a project with a name that resolves to blank shows error", %{
      conn: conn
    } do
      user1 = insert(:user, first_name: "Alice", last_name: "Owner")

      project =
        insert(:project, project_users: [%{role: :owner, user_id: user1.id}])

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      save_project(view, "!!!", %{user1.id => "owner"})

      assert_reply(view, %{fieldErrors: %{"rawName" => [message]}})
      assert message =~ "can't be blank"
      assert Repo.reload!(project).name == project.name
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

      # Add user2 as editor and user3 as viewer
      save_project(view, project.name, %{
        user1.id => "owner",
        user2.id => "editor",
        user3.id => "viewer"
      })

      assert_ok(view)

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

      # A role outside the four is refused rather than read as "no access".
      save_project(view, project.name, %{user2.id => "superuser"})
      assert_reply(view, %{error: "Invalid request"})

      # Remove user2 by giving them no access; user3, left out of the
      # payload, keeps their role.
      save_project(view, project.name, %{user1.id => "owner", user2.id => ""})

      assert_ok(view)

      updated_project = Repo.preload(project, [:project_users], force: true)
      user_ids = Enum.map(updated_project.project_users, & &1.user_id)

      assert user1.id in user_ids
      refute user2.id in user_ids
      assert user3.id in user_ids
    end

    test "hands a project to a new owner in one save", %{conn: conn} do
      user1 = insert(:user, first_name: "Alice", last_name: "Smith")
      user2 = insert(:user, first_name: "Bob", last_name: "Jones")

      project = insert(:project)
      insert(:project_user, project: project, user: user1, role: :owner)
      insert(:project_user, project: project, user: user2, role: :editor)

      {:ok, view, _html} =
        live(conn, ~p"/settings/projects/#{project.id}", on_error: :raise)

      save_project(view, project.name, %{
        user1.id => "editor",
        user2.id => "owner"
      })

      assert_ok(view)

      roles =
        project
        |> Repo.preload([:project_users], force: true)
        |> Map.get(:project_users)
        |> Map.new(&{&1.user_id, &1.role})

      assert roles == %{user1.id => :editor, user2.id => :owner}
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

      # Change user2 from viewer to admin
      save_project(view, project.name, %{
        user1.id => "owner",
        user2.id => "admin"
      })

      assert_ok(view)

      # Check that user2's role was changed
      updated_project = Repo.preload(project, [:project_users], force: true)

      user2_project_user =
        Enum.find(updated_project.project_users, &(&1.user_id == user2.id))

      assert user2_project_user.role == :admin
    end

    test "project owners can delete a project from the settings page",
         %{
           conn: conn,
           project: project
         } do
      {conn, _user} = setup_project_user(conn, project, :owner)

      assert %{"canDeleteProject" => true} =
               conn |> open(project) |> props() |> Map.fetch!("setup")

      view = open(conn, project, "settings/delete")
      assert %{"deleting" => true} = props(view)

      send_event(view, "delete_project", %{"nameConfirmation" => project.name})

      flash = assert_redirect(view, ~p"/projects")
      assert flash["info"] == "Project scheduled for deletion"
      assert Repo.reload(project).scheduled_deletion
    end

    test "project members can export a project", %{conn: conn, project: project} do
      href = conn |> open(project) |> props() |> get_in(["setup", "exportHref"])

      assert href == "/download/yaml?id=#{project.id}"
      assert conn |> get(href) |> response(200)
    end

    test "project members with role other than owner can't delete a project from the settings page",
         %{
           conn: conn,
           project: project
         } do
      ~w(editor admin viewer)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert props(open(conn, project))["setup"]["canDeleteProject"] == false

        {:ok, _delete_project_modal, html} =
          live(conn, ~p"/projects/#{project.id}/settings/delete")
          |> follow_redirect(conn, ~p"/projects/#{project.id}/settings")

        assert html =~ "You are not authorize to perform this action"
      end)
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
      workflow: %{edges: [edge], jobs: [job]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :always})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      # v2 emits the verbose `next:` form with `condition: always` literal
      # (per portability.d.ts:60 the bare-string shortcut is being removed).
      assert response =~ ~s[#{job.name}:\n            condition: always]
    end

    test "having edge with condition_type=on_job_success", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge], jobs: [job]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :on_job_success})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      # v2 emits the named condition literal (per lightning.d.ts:102 union).
      assert response =~ ~s[#{job.name}:\n            condition: on_job_success]
    end

    test "having edge with condition_type=on_job_failure", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge], jobs: [job]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :on_job_failure})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~
               ~s[#{job.name}:\n            condition: on_job_failure]
    end

    test "having edge with condition_type=js_expression", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge], jobs: [job]}
    } do
      edge
      |> Ecto.Changeset.change(%{
        condition_type: :js_expression,
        condition_label: "not underaged",
        condition_expression: "state.data.age > 18"
      })
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      # v2: `condition` IS the JS body (no separate condition_expression);
      # `label` is the optional human-readable string.
      assert response =~
               ~s[#{job.name}:\n            condition: state.data.age > 18]

      assert response =~ ~S[label: not underaged]
    end
  end

  describe "projects picker dropdown" do
    setup :register_and_log_in_user

    defp project_picker(view) do
      picker =
        view
        |> element("#global-project-picker")
        |> render()
        |> Floki.parse_fragment!()

      [items] = Floki.attribute(picker, "data-items")
      [current_id] = Floki.attribute(picker, "data-current-id")

      {current_id, items |> Jason.decode!() |> Map.new(&{&1["id"], &1["label"]})}
    end

    test "the project picker lists the user's projects", %{
      conn: conn,
      user: user
    } do
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

      # Only the user's own projects are offered, the current one marked.
      users_projects = %{
        project_1.id => "project-1",
        project_2.id => "project-2"
      }

      for project <- [project_1, project_2] do
        {:ok, view, _html} =
          live(conn, ~p"/projects/#{project}/w", on_error: :raise)

        assert project_picker(view) == {project.id, users_projects}
      end

      assert live(conn, ~p"/projects/#{project_3}/w", on_error: :raise) ==
               {:error,
                {:redirect, %{flash: %{"nav" => :not_found}, to: "/projects"}}}
    end
  end

  describe "projects settings page" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user
    setup :isolated_adaptors

    setup do
      Lightning.AdaptorTestHelpers.seed_credential_schema("http")
      :ok
    end

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
      %{user: user} =
        Lightning.Projects.get_project_users!(project.id)
        |> List.first()

      assert [
               %{
                 "firstName" => first_name,
                 "lastName" => last_name,
                 "email" => email,
                 "role" => "admin"
               }
             ] =
               conn
               |> open(project)
               |> props()
               |> get_in(["collaboration", "collaborators"])

      assert {first_name, last_name, email} ==
               {user.first_name, user.last_name, user.email}
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

      {:ok, _credential} =
        Lightning.Credentials.create_credential(
          %{
            body: %{},
            name: "some name",
            user_id: user.id,
            schema: "raw",
            project_credentials: [
              %{project_id: project.id}
            ]
          },
          user
        )

      assert [%{"name" => "some name", "schema" => "raw", "ownerEmail" => email}] =
               conn
               |> open(project)
               |> props()
               |> get_in(["credentials", "credentials"])

      assert email == user.email
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

        view = open(conn, project)
        credential_name = build(:credential).name

        assert %{"canCreateProjectCredential" => true, "credentials" => []} =
                 props(view)["credentials"]

        send_event(
          view,
          "create_credential",
          raw_values(%{"name" => credential_name, "projectIds" => [project.id]})
        )

        assert_ok(view)

        assert [%{"name" => ^credential_name}] =
                 props(view)["credentials"]["credentials"]

        assert [%{name: ^credential_name}] =
                 Lightning.Credentials.list_credentials(project)
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

      view = open(conn, project)
      credential_name = build(:credential).name

      assert %{"canCreateProjectCredential" => true, "credentials" => []} =
               props(view)["credentials"]

      send_event(
        view,
        "create_credential",
        raw_values(%{"name" => credential_name, "projectIds" => [project.id]})
      )

      assert_ok(view)

      assert [%{name: ^credential_name, user_id: user_id}] =
               Lightning.Credentials.list_credentials(project)

      assert user_id == user.id
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

      assert %{"canCreateKeychainCredential" => true} =
               conn |> open(project) |> props() |> Map.fetch!("credentials")
    end

    test "excluded credential types do not appear in the type picker grid",
         %{
           conn: conn,
           user: user
         } do
      excluded_types = ["keychain", "googlesheets"]

      Mimic.stub(Lightning.Adaptors, :packages, fn ->
        {:ok,
         [
           %{name: "@openfn/language-http", has_schema: true},
           %{name: "@openfn/language-googlesheets", has_schema: true}
         ]}
      end)

      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      types =
        conn
        |> open(project)
        |> props()
        |> get_in(["credentials", "credentialTypes"])
        |> Enum.map(& &1["key"])

      assert "http" in types

      for type <- excluded_types do
        refute type in types,
               "#{type} should not appear in the credential type picker"
      end
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

      insert(:keychain_credential,
        name: "Test Keychain",
        path: "$.organization.id",
        project: project,
        created_by: user
      )

      # Another project's keychain credential isn't listed.
      other_project =
        insert(:project,
          name: "other-project",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      insert(:keychain_credential,
        name: "Other Project Keychain",
        path: "$.user.department",
        project: other_project,
        created_by: user
      )

      assert [%{"name" => "Test Keychain", "path" => "$.organization.id"}] =
               conn
               |> open(project)
               |> props()
               |> get_in(["credentials", "keychainCredentials"])
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

      view = open(conn, project)

      assert %{
               "keychainCredentials" => [%{"name" => "Test Keychain"}],
               "canEditKeychainCredential" => false
             } = props(view)["credentials"]

      send_event(view, "update_keychain_credential", %{
        "id" => keychain_credential.id,
        "name" => "renamed",
        "path" => "$.id",
        "defaultCredentialId" => nil
      })

      assert_refused(view)
      assert Repo.reload(keychain_credential).name == "Test Keychain"
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

      view = open(conn, project)

      assert [%{"name" => "Test Keychain"}] =
               props(view)["credentials"]["keychainCredentials"]

      assert send_event(view, "delete_keychain_credential", %{
               "id" => keychain_credential.id
             }) =~ "Keychain credential deleted"

      assert_ok(view)
      assert props(view)["credentials"]["keychainCredentials"] == []

      assert Lightning.Credentials.list_keychain_credentials_for_project(project) ==
               []
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

      view = open(conn, project)

      assert %{
               "keychainCredentials" => [%{"name" => "Test Keychain"}],
               "canEditKeychainCredential" => false
             } = props(view)["credentials"]

      send_event(view, "update_keychain_credential", %{
        "id" => keychain_credential.id,
        "name" => "renamed",
        "path" => "$.id",
        "defaultCredentialId" => nil
      })

      assert_refused(view)
      assert Repo.reload(keychain_credential).name == "Test Keychain"
    end

    test "keychain credential delete permissions by role", %{user: user} do
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

      for {member, may_delete} <- [
            {user, true},
            {admin_user, true},
            {editor_user, false},
            {viewer_user, false}
          ] do
        view = build_conn() |> log_in_user(member) |> open(project)

        assert props(view)["credentials"]["canEditKeychainCredential"] ==
                 may_delete

        unless may_delete do
          send_event(view, "delete_keychain_credential", %{
            "id" => keychain_credential.id
          })

          assert_refused(view)
        end
      end

      assert Repo.reload(keychain_credential)
    end

    test "project admin can create keychain credential from settings", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      view = open(conn, project)

      assert send_event(view, "create_keychain_credential", %{
               "name" => "My Keychain Credential",
               "path" => "$.user_id",
               "defaultCredentialId" => nil
             }) =~ "Keychain credential created successfully"

      assert_ok(view)

      keychain_credential =
        Repo.get_by(
          Lightning.Credentials.KeychainCredential,
          name: "My Keychain Credential"
        )

      assert keychain_credential
      assert keychain_credential.created_by_id == user.id
      assert keychain_credential.project_id == project.id
    end

    test "project admin can update keychain credential from settings", %{
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
          created_by: user,
          project: project,
          name: "Original Name",
          path: "$.org_id"
        )

      view = open(conn, project)

      assert send_event(view, "update_keychain_credential", %{
               "id" => keychain_credential.id,
               "name" => "Updated Name",
               "path" => "$.updated_path",
               "defaultCredentialId" => nil
             }) =~ "Keychain credential updated successfully"

      assert_ok(view)

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

      view = open(conn, project)

      send_event(view, "create_keychain_credential", %{
        "name" => "",
        "path" => "",
        "defaultCredentialId" => nil
      })

      assert_reply(view, %{
        fieldErrors: %{
          "name" => ["This field can't be blank."],
          "path" => ["This field can't be blank."]
        }
      })

      assert Lightning.Credentials.list_keychain_credentials_for_project(project) ==
               []
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

      view = open(conn, project)

      assert %{"canCreateKeychainCredential" => false} =
               props(view)["credentials"]

      send_event(view, "create_keychain_credential", %{
        "name" => "new",
        "path" => "$.id",
        "defaultCredentialId" => nil
      })

      assert_refused(view)

      assert Lightning.Credentials.list_keychain_credentials_for_project(project) ==
               []
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

      view = open(conn, project)

      invalid_project_description =
        Enum.map(1..250, fn _ ->
          Enum.random(Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9))
        end)
        |> to_string()

      send_event(view, "save_identity", %{
        "rawName" => "project-1",
        "description" => invalid_project_description
      })

      assert_reply(view, %{
        fieldErrors: %{"description" => ["should be at most 240 character(s)"]}
      })

      assert Repo.reload(project).description == project.description
    end

    test "project settings form cannot change the environment", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "project-1",
          env: "staging",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      view = open(conn, project)

      assert %{"env" => "staging"} = props(view)["setup"]

      send_event(view, "save_identity", %{
        "rawName" => "project-1",
        "env" => "main"
      })

      assert_ok(view)

      assert render_submit(view, "save", %{
               "project" => %{"raw_name" => "project-1", "env" => "main"}
             }) =~ "Project updated successfully"

      assert %{env: "staging"} = Repo.get!(Project, project.id)
    end

    test "saving project settings with name that resolves to blank shows error",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        )

      view = open(conn, project)

      send_event(view, "save_identity", %{"rawName" => "!!!"})

      assert_reply(view, %{
        fieldErrors: %{"rawName" => ["This field can't be blank."]}
      })

      # Project name is unchanged
      assert %{name: "project-1"} = Repo.get!(Project, project.id)
    end

    test "generic save cannot mass-assign privileged fields past their gates",
         %{conn: conn, user: user} do
      other_project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      project =
        insert(:project,
          name: "project-1",
          requires_mfa: false,
          allow_support_access: false,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      view = open(conn, project)

      render_submit(view, "save", %{
        "project" => %{
          "raw_name" => "renamed",
          "requires_mfa" => "true",
          "scheduled_deletion" => "2038-01-01T00:00:00Z",
          "allow_support_access" => "true",
          "parent_id" => other_project.id
        }
      })

      reloaded = Repo.get!(Project, project.id)

      # The ordinary field is applied...
      assert reloaded.name == "renamed"
      # ...but none of the others are.
      refute reloaded.requires_mfa
      assert reloaded.scheduled_deletion == nil
      refute reloaded.allow_support_access
      assert reloaded.parent_id == nil
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

      view = open(conn, project)

      assert send_event(view, "save_concurrency", %{"concurrency" => 1}) =~
               "Project updated successfully"

      assert_ok(view)
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

      view = open(conn, project)

      assert %{"canEditProject" => false} = props(view)["setup"]

      send_event(view, "save_identity", %{"rawName" => "renamed"})
      assert_refused(view)

      assert view |> render_click("save", %{"project" => %{}}) =~
               "You are not authorized to perform this action."

      assert Repo.reload(project).name == "project-1"
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

      view = open(conn, project)

      assert %{"canEditProject" => false} = props(view)["setup"]

      send_event(view, "save_identity", %{"rawName" => "renamed"})
      assert_refused(view)

      assert view |> render_click("save", %{"project" => %{}}) =~
               "You are not authorized to perform this action."

      assert Repo.reload(project).name == "project-1"
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

      view = open(conn, project)

      %{id: own} =
        Enum.find(project.project_users, &(&1.user_id == authenticated_user.id))

      %{id: theirs} =
        Enum.find(
          project.project_users,
          &(&1.user_id == unauthenticated_user.id)
        )

      own_row = fn ->
        Enum.find(
          props(view)["collaboration"]["collaborators"],
          &(&1["id"] == own)
        )
      end

      assert %{"failureAlert" => false, "digest" => "never"} = own_row.()

      refute send_event(view, "set_failure_alert", %{"id" => own, "on" => false}) =~
               "Project user updated successfuly"

      assert_ok(view)

      assert send_event(view, "set_failure_alert", %{"id" => own, "on" => true}) =~
               "Project user updated successfuly"

      assert_ok(view)
      assert %{"failureAlert" => true} = own_row.()

      render_hook(view, "lv:clear-flash", %{key: "info"})

      refute send_event(view, "set_digest", %{"id" => own, "digest" => "never"}) =~
               "Project user updated successfuly"

      assert_ok(view)

      assert send_event(view, "set_digest", %{"id" => own, "digest" => "daily"}) =~
               "Project user updated successfuly"

      assert_ok(view)
      assert %{"digest" => "daily"} = own_row.()

      # Another member's settings are theirs to change.
      send_event(view, "set_failure_alert", %{"id" => theirs, "on" => false})
      assert_refused(view)
      send_event(view, "set_digest", %{"id" => theirs, "digest" => "never"})
      assert_refused(view)

      assert %{failure_alert: true, digest: :daily} =
               Repo.get(Lightning.Projects.ProjectUser, theirs)
    end

    test "all project users can view project security page",
         %{
           conn: conn
         } do
      project = insert(:project)

      [:admin, :owner, :editor, :viewer]
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert %{"requiresMfa" => false, "canEditProject" => can_edit} =
                 conn |> open(project) |> props() |> Map.fetch!("security")

        assert can_edit == role in [:admin, :owner]
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

      view = open(conn, project)

      assert send_event(view, "set_requires_mfa", %{"on" => true}) =~
               "Project MFA requirement updated successfully"

      assert_ok(view)
      assert Repo.reload(project).requires_mfa
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

        view = open(conn, project)

        assert %{"canEditProject" => false} = props(view)["security"]

        send_event(view, "set_requires_mfa", %{"on" => true})
        assert_refused(view)
      end)

      refute Repo.reload(project).requires_mfa
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

    # /mfa_required tells the caller the project exists and how it is
    # configured. Only someone who would otherwise have standing may be told
    # that; a stranger gets the same not-found they get for any other project
    # they are not a member of.
    test "a non-member of an MFA-required project is not told it requires MFA",
         %{conn: conn} do
      stranger = insert(:user, mfa_enabled: false)
      project = insert(:project, requires_mfa: true)

      assert {:error, {:redirect, %{to: "/projects", flash: flash}}} =
               live(
                 log_in_user(conn, stranger),
                 ~p"/projects/#{project}/settings",
                 on_error: :raise
               )

      assert flash == %{"nav" => :not_found}
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

      view = open(conn, project)

      assert send_event(view, "set_support_access", %{"on" => true}) =~
               "Granted access to support users successfully"

      assert_ok(view)
      assert %{allow_support_access: true} = Repo.get(Project, project.id)
      assert props(view)["collaboration"]["supportAccess"]

      assert send_event(view, "set_support_access", %{"on" => false}) =~
               "Revoked access to support users successfully"

      assert_ok(view)
      assert %{allow_support_access: false} = Repo.get(Project, project.id)
      refute props(view)["collaboration"]["supportAccess"]
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

        view = open(conn, project)

        assert props(view)["collaboration"]["canEditProject"] == false

        send_event(view, "set_support_access", %{"on" => true})
        assert_refused(view)

        refute Repo.reload(project).allow_support_access
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

      view = conn |> log_in_user(project_user.user) |> open(project)

      refute has_element?(view, "#project-settings-mfa-banner")
      assert %{"canRequireMfa" => true} = props(view)["security"]

      assert send_event(view, "set_requires_mfa", %{"on" => true}) =~
               "Project MFA requirement updated successfully"

      assert_ok(view)
      assert Repo.reload(project).requires_mfa
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

      view = conn |> log_in_user(project_user.user) |> open(project)

      assert view
             |> element("#project-settings-mfa-banner")
             |> render() =~ banner_message

      assert %{"canRequireMfa" => false} = props(view)["security"]

      send_event(view, "set_requires_mfa", %{"on" => true})
      assert_refused(view)
      refute Repo.reload(project).requires_mfa
    end
  end

  describe "view-extension slot wrappers" do
    test "concurrency_input_slot/1 forwards project, field, and disabled" do
      project = insert(:project)
      changeset = Lightning.Projects.Project.changeset(project, %{})
      form = Phoenix.HTML.FormData.to_form(changeset, [])
      field = form[:concurrency]

      echo =
        render_component(
          &Settings.concurrency_input_slot/1,
          component: LightningWeb.SlotEchoComponent,
          field: field,
          project: project,
          disabled: true
        )
        |> Floki.parse_fragment!()
        |> Floki.find("[data-slot-echo]")

      assert Floki.attribute(echo, "data-project-id") == [project.id]
      assert Floki.attribute(echo, "data-field-id") == [field.id]
      assert Floki.attribute(echo, "data-disabled") == ["true"]
    end

    test "usage_caps_input_slot/1 forwards project and current_user" do
      project = insert(:project)
      user = insert(:user)

      echo =
        render_component(
          &Settings.usage_caps_input_slot/1,
          component: LightningWeb.SlotEchoComponent,
          project: project,
          current_user: user
        )
        |> Floki.parse_fragment!()
        |> Floki.find("[data-slot-echo]")

      assert Floki.attribute(echo, "data-project-id") == [project.id]
      assert Floki.attribute(echo, "data-current-user-id") == [user.id]
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

    test "all project users can see the workflows and channels linked to auth methods" do
      project = insert(:project)
      workflow = insert(:simple_workflow, project: project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          triggers: workflow.triggers
        )

      channel =
        insert(:channel,
          project: project,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :client,
              webhook_auth_method: auth_method
            )
          ]
        )

      for conn <-
            build_project_user_conns(project, [:editor, :admin, :owner, :viewer]) do
        assert [
                 %{
                   "name" => name,
                   "triggers" => [%{"name" => trigger_name}],
                   "channels" => [%{"name" => channel_name}]
                 }
               ] =
                 conn
                 |> open(project)
                 |> props()
                 |> get_in(["webhookSecurity", "authMethods"])

        assert {name, trigger_name, channel_name} ==
                 {auth_method.name, workflow.name, channel.name}
      end
    end

    test "auth methods with no triggers or channels have no usage link" do
      project = insert(:project)
      insert(:webhook_auth_method, project: project)

      [conn] = build_project_user_conns(project, [:owner])

      assert [%{"triggers" => [], "channels" => []}] =
               conn
               |> open(project)
               |> props()
               |> get_in(["webhookSecurity", "authMethods"])
    end

    test "owners/admins can add a new project webhook auth method, editors/viewers can't" do
      project = insert(:project)

      for conn <- build_project_user_conns(project, [:owner, :admin]) do
        view = open(conn, project)

        assert props(view)["webhookSecurity"]["canWrite"]

        credential_name = build(:credential).name

        assert send_event(view, "create_webhook_auth_method", %{
                 "authType" => "basic",
                 "name" => credential_name,
                 "username" => "testusername",
                 "password" => "testpassword123"
               }) =~ "Webhook auth method created successfully"

        assert_ok(view)

        assert Enum.any?(
                 props(view)["webhookSecurity"]["authMethods"],
                 &(&1["name"] == credential_name)
               )
      end

      for conn <- build_project_user_conns(project, [:editor, :viewer]) do
        view = open(conn, project)

        refute props(view)["webhookSecurity"]["canWrite"]

        send_event(view, "create_webhook_auth_method", %{
          "authType" => "basic",
          "name" => "not allowed",
          "username" => "testusername",
          "password" => "testpassword123"
        })

        assert_refused(view)
      end

      assert length(Lightning.WebhookAuthMethods.list_for_project(project)) == 2
    end

    test "owners/admins can add edit a project webhook auth method, editors/viewers can't" do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic
        )

      names =
        for conn <- build_project_user_conns(project, [:owner, :admin]) do
          view = open(conn, project)
          credential_name = build(:credential).name

          assert send_event(view, "rename_webhook_auth_method", %{
                   "id" => auth_method.id,
                   "name" => credential_name
                 }) =~ "Webhook auth method updated successfully"

          assert_ok(view)

          assert [%{"name" => ^credential_name}] =
                   props(view)["webhookSecurity"]["authMethods"]

          credential_name
        end

      for conn <- build_project_user_conns(project, [:editor, :viewer]) do
        view = open(conn, project)

        refute props(view)["webhookSecurity"]["canWrite"]

        send_event(view, "rename_webhook_auth_method", %{
          "id" => auth_method.id,
          "name" => "not allowed"
        })

        assert_refused(view)
      end

      assert Repo.reload(auth_method).name == List.last(names)
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

      view = conn |> log_in_user(project_user.user) |> open(project)

      # Only the last five characters are shown.
      assert [%{"maskedSecret" => masked}] =
               props(view)["webhookSecurity"]["authMethods"]

      assert masked == String.duplicate("*", 15) <> "y1234"
      refute render(view) =~ auth_method.api_key

      send_event(view, "reveal_webhook_secret", %{
        "id" => auth_method.id,
        "password" => "wrongpass",
        "code" => ""
      })

      assert_reply(view, %{error: "Invalid! Please try again"})

      send_event(view, "reveal_webhook_secret", %{
        "id" => auth_method.id,
        "password" => project_user.user.password,
        "code" => ""
      })

      assert_reply(view, %{secret: secret})
      assert secret == auth_method.api_key
      refute render(view) =~ auth_method.api_key
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

      view = conn |> log_in_user(project_user.user) |> open(project)

      assert [%{"maskedSecret" => masked}] =
               props(view)["webhookSecurity"]["authMethods"]

      assert masked ==
               String.duplicate("*", String.length(auth_method.password))

      refute render(view) =~ auth_method.password

      send_event(view, "reveal_webhook_secret", %{
        "id" => auth_method.id,
        "password" => "wrongpass",
        "code" => ""
      })

      assert_reply(view, %{error: "Invalid! Please try again"})

      send_event(view, "reveal_webhook_secret", %{
        "id" => auth_method.id,
        "password" => project_user.user.password,
        "code" => ""
      })

      assert_reply(view, %{secret: secret})
      assert secret == auth_method.password
      refute render(view) =~ auth_method.password
    end

    test "an auth method lists its triggers and channels with links to each" do
      project = insert(:project)
      workflow = insert(:simple_workflow, project: project, name: "My Workflow")
      [%{id: trigger_id}] = workflow.triggers

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          triggers: workflow.triggers
        )

      channel =
        insert(:channel,
          project: project,
          name: "My Channel",
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :client,
              webhook_auth_method: auth_method
            )
          ]
        )

      [conn] = build_project_user_conns(project, [:owner])

      assert [
               %{
                 "triggers" => [
                   %{"name" => "My Workflow", "href" => trigger_href}
                 ],
                 "channels" => [
                   %{"name" => "My Channel", "href" => channel_href}
                 ]
               }
             ] =
               conn
               |> open(project)
               |> props()
               |> get_in(["webhookSecurity", "authMethods"])

      assert trigger_href ==
               "/projects/#{project.id}/w/#{workflow.id}?s=#{trigger_id}"

      assert channel_href ==
               "/projects/#{project.id}/channels/#{channel.id}/edit"
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

        view = conn |> log_in_user(project_user.user) |> open(project)

        assert Enum.any?(
                 props(view)["webhookSecurity"]["authMethods"],
                 &(&1["id"] == auth_method.id)
               )

        assert send_event(view, "delete_webhook_auth_method", %{
                 "id" => auth_method.id
               }) =~ "Your Webhook Authentication method has been deleted."

        assert_ok(view)
        assert Repo.reload(auth_method).scheduled_deletion

        refute Enum.any?(
                 props(view)["webhookSecurity"]["authMethods"],
                 &(&1["id"] == auth_method.id)
               )
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

        view = conn |> log_in_user(project_user.user) |> open(project)

        send_event(view, "delete_webhook_auth_method", %{"id" => auth_method.id})
        assert_refused(view)
        refute Repo.reload(auth_method).scheduled_deletion
      end
    end
  end

  describe "data-storage" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    @tag role: :owner
    test "project owner can view these settings", %{conn: conn, project: project} do
      assert %{"canEdit" => true} =
               conn |> open(project) |> props() |> Map.fetch!("dataStorage")
    end

    @tag role: :admin
    test "project admin can view these settings", %{conn: conn, project: project} do
      # retain_all is the default
      assert %{
               "canEdit" => true,
               "retentionPolicy" => "retain_all",
               "historyRetentionPeriod" => nil,
               "dataclipRetentionPeriod" => nil
             } = conn |> open(project) |> props() |> Map.fetch!("dataStorage")
    end

    @tag role: :editor
    test "project editor does not have permission", %{
      conn: conn,
      project: project
    } do
      view = open(conn, project)

      assert %{"canEdit" => false} = props(view)["dataStorage"]

      send_event(view, "save_data_storage", %{
        "retentionPolicy" => "retain_all",
        "historyRetentionPeriod" => 14,
        "dataclipRetentionPeriod" => 7
      })

      assert_refused(view)
      assert Repo.reload(project).history_retention_period == nil
    end

    @tag role: :viewer
    test "project viewer does not have permission", %{
      conn: conn,
      project: project
    } do
      view = open(conn, project)

      assert %{"canEdit" => false} = props(view)["dataStorage"]

      send_event(view, "save_data_storage", %{
        "retentionPolicy" => "retain_all",
        "historyRetentionPeriod" => 14,
        "dataclipRetentionPeriod" => 7
      })

      assert_refused(view)
      assert Repo.reload(project).history_retention_period == nil
    end

    @tag role: :admin
    test "project admin can change the Input/Output Data Storage Policy", %{
      conn: conn,
      project: project
    } do
      # save, open the page again and the saved option is the one shown
      # TODO - retain_with_errors will be added in https://github.com/OpenFn/Lightning/issues/1694
      for policy <- ["erase_all", "retain_all"] do
        view = open(conn, project)

        assert send_event(view, "save_data_storage", %{
                 "retentionPolicy" => policy
               }) =~ "Project updated successfully"

        assert_ok(view)

        assert policy ==
                 project.id
                 |> Projects.get_project!()
                 |> Map.get(:retention_policy)
                 |> Atom.to_string()

        assert %{"retentionPolicy" => ^policy} =
                 conn |> open(project) |> props() |> Map.fetch!("dataStorage")
      end
    end

    @tag role: :admin
    test "history retention period only shows provided options by the extension",
         %{
           conn: conn,
           project: %{id: project_id} = project
         } do
      expect(
        Lightning.Extensions.MockUsageLimiter,
        :get_data_retention_periods,
        2,
        fn %{project_id: ^project_id} ->
          [7, 14]
        end
      )

      assert %{"periods" => [7, 14]} =
               conn |> open(project) |> props() |> Map.fetch!("dataStorage")
    end

    @tag role: :admin
    test "project admin can change the retention periods", %{
      conn: conn,
      project: project
    } do
      view = open(conn, project)

      # a dataclip retention period longer than the history period is refused
      send_event(view, "save_data_storage", %{
        "historyRetentionPeriod" => 7,
        "dataclipRetentionPeriod" => 14
      })

      assert_reply(view, %{
        fieldErrors: %{
          "dataclipRetentionPeriod" => [
            "dataclip retention period must be less or equal to the history retention period"
          ]
        }
      })

      # the project gets updated successfully
      assert send_event(view, "save_data_storage", %{
               "historyRetentionPeriod" => 7,
               "dataclipRetentionPeriod" => 7
             }) =~ "Project updated successfully"

      assert_ok(view)

      assert %{history_retention_period: 7, dataclip_retention_period: 7} =
               Repo.reload(project)
    end

    @tag role: :admin
    test "creates event linked to user when retention period is updated", %{
      conn: conn,
      project: project,
      user: %{id: user_id}
    } do
      view = open(conn, project)

      send_event(view, "save_data_storage", %{"historyRetentionPeriod" => 7})
      assert_ok(view)

      assert %{actor_id: ^user_id} = Audit |> Repo.one!()
    end

    @tag role: :admin
    test "indicates if there was a failure due to audit creation", %{
      conn: conn,
      project: project
    } do
      view = open(conn, project)

      with_mock(Lightning.Repo, [:passthrough],
        transaction: fn _multi ->
          {:error, :anything_other_than_project, %Ecto.Changeset{}, %{}}
        end
      ) do
        send_event(view, "save_data_storage", %{"historyRetentionPeriod" => 7})

        assert_reply(view, %{
          error: "Changes couldn't be saved, please try again"
        })
      end

      assert Repo.reload(project).history_retention_period == nil
    end
  end

  describe "projects settings:collaboration" do
    setup :register_and_log_in_user

    defp collaborator(view, project_user_id) do
      Enum.find(
        props(view)["collaboration"]["collaborators"],
        &(&1["id"] == project_user_id)
      )
    end

    test "only authorized users can add collaborators", %{conn: conn} do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        view = open(conn, project)

        assert %{
                 "canAddProjectUser" => false,
                 "addBlockedReason" =>
                   "You are not authorized to perform this action"
               } = props(view)["collaboration"]

        send_event(view, "add_collaborators", %{
          "collaborators" => [
            %{"email" => insert(:user).email, "role" => "editor"}
          ]
        })

        assert_refused(view)
      end

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        assert %{"canAddProjectUser" => true, "addBlockedReason" => nil} =
                 conn |> open(project) |> props() |> Map.fetch!("collaboration")
      end

      assert length(Repo.preload(project, :project_users).project_users) == 4
    end

    test "adding a collaborator with an invalid email replies its error", %{
      conn: conn
    } do
      project = insert(:project)
      {conn, _user} = setup_project_user(conn, project, :owner)
      view = open(conn, project)

      send_event(view, "add_collaborators", %{
        "collaborators" => [%{"email" => "not-an-email", "role" => "editor"}]
      })

      assert_reply(view, %{error: "Email address not valid."})
    end

    test "inviting a collaborator with an invalid email puts the error on its row",
         %{conn: conn} do
      project = insert(:project, name: "my-project")
      {conn, _user} = setup_project_user(conn, project, :owner)
      view = open(conn, project)

      send_event(view, "invite_collaborators", %{
        "collaborators" => [
          %{
            "email" => "not-an-email",
            "role" => "editor",
            "firstName" => "Test",
            "lastName" => "User"
          }
        ]
      })

      assert_reply(view, %{
        fieldErrors: %{
          "invitedCollaborators.0.email" => ["Email address not valid."]
        }
      })
    end

    test "adding a non existent user triggers the invite users process", %{
      conn: conn
    } do
      project = insert(:project, name: "my-project")
      {conn, _user} = setup_project_user(conn, project, :owner)
      view = open(conn, project)

      email = "nonexists@localtests.com"

      send_event(view, "add_collaborators", %{
        "collaborators" => [%{"email" => email, "role" => "editor"}]
      })

      assert_reply(view, %{toInvite: [%{email: ^email, role: :editor}]})

      assert send_event(view, "invite_collaborators", %{
               "collaborators" => [
                 %{
                   "email" => email,
                   "role" => "editor",
                   "firstName" => "Non",
                   "lastName" => "Exists"
                 }
               ]
             }) =~ "Invite sent successfully"

      assert_ok(view)

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
      view = open(conn, project)

      send_event(view, "invite_collaborators", %{
        "collaborators" => [
          %{
            "email" => user.email,
            "role" => "editor",
            "firstName" => "Non",
            "lastName" => "Exists"
          }
        ]
      })

      assert_reply(view, %{
        fieldErrors: %{
          "invitedCollaborators.0.email" => ["This email is already taken"]
        }
      })

      refute_email_sent(subject: "Join my-project on OpenFn as a collaborator")
    end

    test "adding an existing project user displays an appropriate error message",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        view = open(conn, project)

        send_event(view, "add_collaborators", %{
          "collaborators" => [%{"email" => user.email, "role" => "editor"}]
        })

        assert_reply(view, %{
          error: "This account is already part of this project"
        })
      end
    end

    test "adding an owner project user is not allowed",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        other = insert(:user)
        view = open(conn, project)

        send_event(view, "add_collaborators", %{
          "collaborators" => [%{"email" => other.email, "role" => "owner"}]
        })

        assert_reply(view, %{error: "is invalid"})
        refute Projects.get_project_user(project, other)
      end
    end

    test "user can add collaborators successfully",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        view = open(conn, project)
        [admin, editor, viewer] = insert_list(3, :user)

        assert send_event(view, "add_collaborators", %{
                 "collaborators" => [
                   %{"email" => admin.email, "role" => "admin"},
                   %{"email" => editor.email, "role" => "editor"},
                   %{"email" => viewer.email, "role" => "viewer"}
                 ]
               }) =~ "Collaborators added successfully"

        assert_reply(view, %{toInvite: []})

        assert [:admin, :editor, :viewer] ==
                 Enum.map(
                   [admin, editor, viewer],
                   &Projects.get_project_user(project, &1).role
                 )

        emails =
          Enum.map(props(view)["collaboration"]["collaborators"], & &1["email"])

        assert Enum.all?([admin, editor, viewer], &(&1.email in emails))
      end
    end

    test "adding collaborators is blocked if limit is reached", %{
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

      view = open(conn, project)

      assert %{"canAddProjectUser" => true, "addBlockedReason" => ^error_msg} =
               props(view)["collaboration"]

      other = insert(:user)

      send_event(view, "add_collaborators", %{
        "collaborators" => [%{"email" => other.email, "role" => "editor"}]
      })

      assert_reply(view, %{error: ^error_msg})
      refute Projects.get_project_user(project, other)
    end

    test "error message is displayed if the allowed limits are exceeded", %{
      conn: conn
    } do
      %{id: project_id} = project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      # users to add
      [admin, editor, viewer] = users = insert_list(3, :user)

      # we only want to allow 3 users. We already 1, the one logged in
      expected_error_msg = "You can only have 3 collaborators in this project"

      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :new_user, amount: 3}, %{project_id: ^project_id} ->
            {:error, :too_many_users, %{text: expected_error_msg}}

          _action, _project ->
            :ok
        end
      )

      view = open(conn, project)

      assert props(view)["collaboration"]["addBlockedReason"] == nil

      send_event(view, "add_collaborators", %{
        "collaborators" => [
          %{"email" => admin.email, "role" => "admin"},
          %{"email" => editor.email, "role" => "editor"},
          %{"email" => viewer.email, "role" => "viewer"}
        ]
      })

      assert_reply(view, %{error: ^expected_error_msg})

      for user <- users, do: refute(Projects.get_project_user(project, user))
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

        view = open(conn, project)

        assert collaborator(view, project_user.id)["removeBlockedReason"] ==
                 "You do not have permission to remove a user"

        send_event(view, "remove_collaborator", %{"id" => project_user.id})
        assert_refused(view)

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

        view = open(conn, project)

        assert collaborator(view, project_user.id)["removeBlockedReason"] == nil

        assert send_event(view, "remove_collaborator", %{
                 "id" => project_user.id
               }) =~ "Collaborator removed"

        assert_ok(view)
        refute collaborator(view, project_user.id)

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

      view = open(conn, project)

      assert collaborator(view, project_owner.id)["removeBlockedReason"] ==
               "You cannot remove an owner"

      send_event(view, "remove_collaborator", %{"id" => project_owner.id})
      assert_refused(view)

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

        view = open(conn, project)

        assert collaborator(view, project_user.id)["removeBlockedReason"] ==
                 "You cannot remove yourself"

        send_event(view, "remove_collaborator", %{"id" => project_user.id})
        assert_refused(view)

        # project user still exists
        assert Repo.get(Lightning.Projects.ProjectUser, project_user.id)
      end
    end

    test "cannot remove a collaborator belonging to another project", %{
      conn: conn
    } do
      project_a = insert(:project)
      {conn, _admin} = setup_project_user(conn, project_a, :admin)

      project_b = insert(:project)

      other =
        insert(:project_user,
          project: project_b,
          user: build(:user),
          role: :editor
        )

      view = open(conn, project_a)

      send_event(view, "remove_collaborator", %{"id" => other.id})
      assert_refused(view)
      assert Repo.get(Lightning.Projects.ProjectUser, other.id)
    end

    test "cannot toggle failure alert for a collaborator in another project",
         %{conn: conn} do
      assert_cross_project_pref_refused(
        conn,
        "set_failure_alert",
        {"on", false},
        :failure_alert,
        true
      )
    end

    test "cannot set digest for a collaborator in another project", %{
      conn: conn
    } do
      assert_cross_project_pref_refused(
        conn,
        "set_digest",
        {"digest", "daily"},
        :digest,
        :never
      )
    end

    test "cannot toggle failure alert for another member of the same project", %{
      conn: conn
    } do
      project = insert(:project)
      {conn, _admin} = setup_project_user(conn, project, :admin)

      other =
        insert(:project_user,
          project: project,
          user: build(:user),
          failure_alert: true
        )

      view = open(conn, project)

      send_event(view, "set_failure_alert", %{"id" => other.id, "on" => false})
      assert_refused(view)
      assert Repo.reload(other).failure_alert == true
    end

    test "cannot set digest for another member of the same project", %{
      conn: conn
    } do
      project = insert(:project)
      {conn, _admin} = setup_project_user(conn, project, :admin)

      other =
        insert(:project_user,
          project: project,
          user: build(:user),
          digest: :never
        )

      view = open(conn, project)

      send_event(view, "set_digest", %{"id" => other.id, "digest" => "daily"})
      assert_refused(view)
      assert Repo.reload(other).digest == :never
    end

    test "a member can still toggle their own failure alert", %{conn: conn} do
      project = insert(:project)
      {conn, user} = setup_project_user(conn, project, :editor)

      pu =
        Repo.get_by(Lightning.Projects.ProjectUser,
          user_id: user.id,
          project_id: project.id
        )

      view = open(conn, project)

      target = !pu.failure_alert

      send_event(view, "set_failure_alert", %{"id" => pu.id, "on" => target})
      assert_ok(view)

      assert Repo.reload(pu).failure_alert == target
      assert collaborator(view, pu.id)["failureAlert"] == target
    end

    test "a member can still set their own digest", %{conn: conn} do
      project = insert(:project)
      {conn, user} = setup_project_user(conn, project, :editor)

      pu =
        Repo.get_by(Lightning.Projects.ProjectUser,
          user_id: user.id,
          project_id: project.id
        )

      view = open(conn, project)

      send_event(view, "set_digest", %{"id" => pu.id, "digest" => "weekly"})
      assert_ok(view)

      assert Repo.reload(pu).digest == :weekly
      assert collaborator(view, pu.id)["digest"] == "weekly"
    end

    # The three events that take a collaborator id look it up the same way
    # (`Projects.get_project_user_for_project/3`); an id that isn't a string
    # finds no one, so each event is refused rather than crashing the view.
    test "a non-binary collaborator id is refused without crashing the view",
         %{conn: conn} do
      project = insert(:project)
      {conn, _admin} = setup_project_user(conn, project, :admin)

      view = open(conn, project)

      for {event, payload} <- [
            {"remove_collaborator", %{"id" => ["x"]}},
            {"set_failure_alert", %{"id" => ["x"], "on" => true}},
            {"set_digest", %{"id" => ["x"], "digest" => "weekly"}}
          ] do
        send_event(view, event, payload)
        assert_refused(view)
      end

      assert Process.alive?(view.pid)
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

      view = open(conn, project)

      assert props(view)["collaboration"]["canReceiveFailureAlerts"]
      assert collaborator(view, project_user.id)["failureAlert"]

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

      # the page shows the status as Unavailable, even though it is enabled
      # on the project user
      view = open(conn, project)

      refute props(view)["collaboration"]["canReceiveFailureAlerts"]
      assert collaborator(view, project_user.id)["failureAlert"]
    end

    test "a collaborator lists the names of the credentials they own in the project",
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

      view = open(conn, project)

      assert collaborator(view, project_user.id)["ownedCredentialNames"] == [
               credential.name
             ]

      credential2 =
        insert(:credential,
          name: "PostgreSQL",
          user: user_to_remove,
          project_credentials: [%{project_id: project.id}]
        )

      view = open(conn, project)

      assert Enum.sort(
               collaborator(view, project_user.id)["ownedCredentialNames"]
             ) ==
               Enum.sort([credential.name, credential2.name])
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
        assert %{"enabled" => false, "connectAccountHref" => ""} =
                 conn |> open(project) |> props() |> Map.fetch!("githubSync")
      end
    end

    test "authorized users get option to connect their github account if they havent done so",
         %{conn: conn} do
      project = insert(:project)

      # unauthorized users don't get any option at all
      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor]) do
        assert %{"enabled" => true, "canInstall" => false} =
                 conn |> open(project) |> props() |> Map.fetch!("githubSync")
      end

      # authorized users
      for {conn, _user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        view = open(conn, project)

        assert %{
                 "enabled" => true,
                 "canInstall" => true,
                 "userConnected" => false,
                 "connectAccountHref" => "https://github.com/login/oauth/" <> _
               } = props(view)["githubSync"]

        refute has_element?(view, "#project-repo-connection-form")
      end
    end

    test "authorized users see form to connect branch if they have already connected their github account",
         %{conn: conn} do
      project = insert(:project)

      # unauthorized users don't see the form at all
      for {conn, user} <-
            setup_project_users(conn, project, [:viewer, :editor]) do
        set_valid_github_oauth_token!(user)

        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        assert %{
                 "enabled" => true,
                 "userConnected" => true,
                 "canInstall" => false
               } =
                 props(view)["githubSync"]

        refute html =~ "Create/update GitHub installations"
      end

      # authorized users
      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        assert %{
                 "enabled" => true,
                 "userConnected" => true,
                 "canInstall" => true
               } =
                 props(view)["githubSync"]

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

      view = open(conn, project, "settings#vcs")

      assert %{"userConnected" => false} = props(view)["githubSync"]
      refute has_element?(view, "#project-repo-connection-form")

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      flash = assert_redirect(view, ~p"/projects/#{project.id}/settings#vcs")

      assert flash["info"] == "GitHub account linked successfully"

      view = open(conn, project, "settings#vcs")
      render_async(view)

      assert %{"userConnected" => true} = props(view)["githubSync"]
      assert has_element?(view, "#project-repo-connection-form")
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

      view = open(conn, project, "settings#vcs")

      assert %{"userConnected" => false} = props(view)["githubSync"]

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      :ok = refute_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

      assert render(view) =~
               "Oops! GitHub account failed to link. Please try again"

      # the account is still to connect
      assert %{"userConnected" => false} = props(view)["githubSync"]
      refute has_element?(view, "#project-repo-connection-form")
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
      assert options |> hd() |> Floki.raw_html() =~ "Select an installation"

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
      assert Floki.raw_html(default_option) =~ "Select an installation"

      assert Floki.raw_html(installation_option) =~
               "#{expected_installation["account"]["type"]}: #{expected_installation["account"]["login"]}"
    end

    test "does not show error banner when installations load successfully", %{
      conn: conn
    } do
      project = insert(:project)
      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{
        "installations" => [
          %{
            "id" => 1234,
            "account" => %{"type" => "User", "login" => "username"}
          }
        ]
      })

      expect_create_installation_token(1234)
      expect_get_installation_repos(200)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      html = render_async(view)

      refute html =~ "Unable to load GitHub installations"
      refute html =~ "No GitHub installations found"
    end

    test "shows warning banner when user has no GitHub installations", %{
      conn: conn
    } do
      project = insert(:project)
      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(200, %{"installations" => []})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      html = render_async(view)

      assert html =~ "No GitHub installations found"
      assert html =~ "You haven&#39;t installed the OpenFn GitHub App yet"
    end

    test "an expired OAuth token asks the user to connect their account again",
         %{conn: conn} do
      project = insert(:project)
      {conn, user} = setup_project_user(conn, project, :admin)
      set_expired_github_oauth_token!(user)

      view = open(conn, project, "settings#vcs")

      # The form needs a valid token, so it isn't drawn and nothing is
      # asked of GitHub.
      assert %{"canInstall" => true, "userConnected" => false} =
               props(view)["githubSync"]

      refute has_element?(view, "#github-sync-component")
    end

    test "shows error banner when GitHub API returns an error", %{
      conn: conn
    } do
      project = insert(:project)
      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      expect_get_user_installations(500, %{"error" => "Internal Server Error"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      html = render_async(view)

      assert html =~ "Unable to load GitHub installations"
      assert html =~ "There was a problem connecting to GitHub"
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
      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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

      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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

    test "does not fetch branches from a github installation the user cannot access",
         %{conn: conn} do
      own_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      own_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      # An installation belonging to another tenant. The shared GitHub App's
      # private key can mint a token for it, so the branch fetch must refuse
      # before reaching for the app credential.
      foreign_installation_id = "9999"
      foreign_repo = "otheraccount/private-repo"

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :owner)
      set_valid_github_oauth_token!(user)

      # On mount the user only sees their own installation (1234) and its repos.
      expect_get_user_installations(200, %{
        "installations" => [own_installation]
      })

      expect_create_installation_token(own_installation["id"])
      expect_get_installation_repos(200, %{"repositories" => [own_repo]})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      # Attempt to list branches for the FOREIGN installation. The only GitHub
      # call the happy path should make is the /user/installations membership
      # check, which returns 1234 only. We deliberately set NO
      # expect_create_installation_token/expect_get_repo_branches for the
      # foreign id, so if the code tried to mint an app token or fetch branches
      # the strict Mox adapter would raise.
      expect_get_user_installations(200, %{
        "installations" => [own_installation]
      })

      view
      |> form("#project-repo-connection-form")
      |> render_change(
        connection: %{
          github_installation_id: foreign_installation_id,
          repo: foreign_repo
        }
      )

      options =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> Floki.parse_fragment!()
        |> Floki.find("#select-branches-input li")

      # Only the "Select a branch" prompt is present; no branches leaked.
      assert Enum.count(options) == 1
      refute find_selected_option(Floki.raw_html(options), "li")

      # The same guarantee holds when explicitly refreshing branches.
      expect_get_user_installations(200, %{
        "installations" => [own_installation]
      })

      view |> element("#refresh-branches-button") |> render_click()

      options =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> Floki.parse_fragment!()
        |> Floki.find("#select-branches-input li")

      assert Enum.count(options) == 1
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
      assert Floki.raw_html(default_option) =~ "Select an installation"

      assert Floki.raw_html(installation_option) =~
               "#{expected_installation["account"]["type"]}: #{expected_installation["account"]["login"]}"

      # before selecting any installation the repos are not listed.
      # We just have the default option
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [repos_input] = Floki.find(floki_fragment, "#select-repos-input")
      options = Floki.children(repos_input)
      assert Enum.count(options) == 1
      assert options |> hd() |> Floki.raw_html() =~ "Select a repo"

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
      assert Floki.raw_html(default_option) =~ "Select a repo"
      assert Floki.raw_html(repo_option) =~ expected_repo["full_name"]

      # before selecting any repo, the branches are not listed.
      # We just have the default option

      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [branches_input] = Floki.find(floki_fragment, "#select-branches-input")
      options = Floki.children(branches_input)
      assert Enum.count(options) == 1
      assert options |> hd() |> Floki.raw_html() =~ "Select a branch"

      # lets select the repo
      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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
      assert Floki.raw_html(default_option) =~ "Select a branch"
      assert Floki.raw_html(branch_option) =~ expected_branch["name"]

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
      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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
      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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
      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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
      assert flash["error"] == "GitHub Error: #{expected_error_msg}"
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
      expect_get_user_installations(200, %{
        "installations" => [expected_installation]
      })

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
      assert flash["error"] == "GitHub Error: #{expected_error_msg}"
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

    test "all users can see a saved repo connection", %{conn: conn} do
      project = insert(:project)

      insert(:project_repo_connection,
        project: project,
        repo: "someaccount/somerepo",
        branch: "somebranch",
        github_installation_id: "1234"
      )

      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        view = open(conn, project, "settings#vcs")

        refute has_element?(view, "#project-repo-connection-form")

        assert %{
                 "repo" => "someaccount/somerepo",
                 "branch" => "somebranch",
                 "githubInstallationId" => "1234"
               } = props(view)["githubSync"]["connection"]
      end
    end

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

        view = open(conn, project, "settings#vcs")

        refute props(view)["githubSync"]["canInstall"]

        send_event(view, "remove_github_connection")
        assert_refused(view)

        assert Lightning.Repo.reload(repo_connection)
      end
    end

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

        view = open(conn, project, "settings#vcs")

        assert props(view)["githubSync"]["canInstall"]

        assert send_event(view, "remove_github_connection") =~
                 "Connection removed successfully"

        assert_ok(view)

        refute Lightning.Repo.reload(repo_connection)
        assert props(view)["githubSync"]["connection"] == nil

        assert Repo.get_by(Audit,
                 item_id: project.id,
                 event: "repo_connection_removed",
                 actor_id: user.id
               )
      end
    end

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

        view = open(conn, project, "settings#vcs")

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

        assert send_event(view, "remove_github_connection") =~
                 "Connection removed successfully"

        assert_ok(view)

        refute Lightning.Repo.reload(repo_connection)
      end
    end

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

        view = open(conn, project, "settings#vcs")

        refute props(view)["githubSync"]["canInitiateSync"]

        # nothing is asked of GitHub
        send_event(view, "sync_github")
        assert_refused(view)
      end
    end

    test "initiating a sync on a project whose names collide says which ones", %{
      conn: conn
    } do
      project = insert(:project)

      insert(:project_repo_connection,
        project: project,
        repo: "someaccount/somerepo",
        branch: "somebranch",
        github_installation_id: "1234",
        access_token: "someaccesstoken"
      )

      # Both hyphenate to `My-Flow`. The export pre-flight refuses before any
      # GitHub call, so no sync mocks are set.
      for name <- ["My Flow", "My-Flow"] do
        {:ok, _} =
          insert(:simple_workflow, name: name, project: project)
          |> Lightning.Workflows.Snapshot.create()
      end

      [{conn, user}] = setup_project_users(conn, project, [:admin])
      set_valid_github_oauth_token!(user)

      view = open(conn, project, "settings#vcs")

      send_event(view, "sync_github")
      assert_reply(view, %{error: error})

      assert error =~ "two workflows in this project"
      assert error =~ ~s("My Flow")
      assert error =~ ~s("My-Flow")
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

        view = open(conn, project, "settings#vcs")

        assert props(view)["githubSync"]["canInitiateSync"]

        expect_create_installation_token(repo_connection.github_installation_id)
        expect_get_repo(repo_connection.repo)
        expect_create_workflow_dispatch(repo_connection.repo, "openfn-pull.yml")

        assert send_event(view, "sync_github") =~ "GitHub sync initiated"
        assert_ok(view)
      end
    end

    test "authorized users get an error when initiating github sync if the usage limiter returns an error",
         %{
           conn: conn
         } do
      %{id: project_id} = project = insert(:project)

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
        view = open(conn, project, "settings#vcs")

        refute props(view)["githubSync"]["canInitiateSync"]

        # The limit has no text, so the sync replies the general error;
        # nothing is asked of GitHub.
        send_event(view, "sync_github")

        assert_reply(view, %{
          error:
            "Oops! An error occurred while connecting to GitHub. Please try again later"
        })
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

    test "only authorized users can create a collection", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        view = open(conn, project, "settings#collections")

        refute props(view)["collections"]["canManage"]

        send_event(view, "create_collection", %{"rawName" => "not allowed"})
        assert_refused(view)
      end

      for {conn, _user} <-
            setup_project_users(conn, project, [:owner, :admin]) do
        assert conn
               |> open(project, "settings#collections")
               |> props()
               |> get_in(["collections", "canManage"])
      end

      assert Lightning.Collections.list_project_collections(project) == []
    end

    test "user can create collection successfully", %{
      conn: conn
    } do
      project = insert(:project)

      for {{conn, _user}, index} <-
            setup_project_users(conn, project, [:owner, :admin])
            |> Enum.with_index() do
        view = open(conn, project, "settings#collections")

        collection_name = "test collection #{index}"
        expected_collection_name = String.replace(collection_name, " ", "-")

        # collection does not exist
        refute Lightning.Repo.get_by(Lightning.Collections.Collection,
                 project_id: project.id,
                 name: expected_collection_name
               )

        assert send_event(view, "create_collection", %{
                 "rawName" => collection_name
               }) =~ "Collection created"

        assert_ok(view)

        # collection now exists
        assert Lightning.Repo.get_by(Lightning.Collections.Collection,
                 project_id: project.id,
                 name: expected_collection_name
               )

        assert Enum.any?(
                 props(view)["collections"]["collections"],
                 &(&1["name"] == expected_collection_name)
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

      view = open(conn, project, "settings#collections")

      send_event(view, "create_collection", %{"rawName" => collection.name})

      assert_reply(view, %{
        fieldErrors: %{
          "rawName" => ["A collection with this name already exists"]
        }
      })
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

      view = open(conn, project, "settings#collections")

      send_event(view, "create_collection", %{"rawName" => "some name"})
      assert_reply(view, %{error: ^error_msg})

      assert Lightning.Collections.list_project_collections(project) == []
    end

    test "unauthorized users cannot edit a collection", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        collection = insert(:collection, project: project)

        view = open(conn, project, "settings#collections")

        send_event(view, "rename_collection", %{
          "id" => collection.id,
          "rawName" => "renamed"
        })

        assert_refused(view)
        assert Repo.reload(collection).name == collection.name
      end
    end

    test "authorized users can edit a collection successfully", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:owner, :admin]) do
        collection = insert(:collection, project: project)

        view = open(conn, project, "settings#collections")

        new_collection_name = "#{collection.name}-#{collection.id}"

        # collection does not exist
        refute Lightning.Repo.get_by(Lightning.Collections.Collection,
                 project_id: project.id,
                 name: new_collection_name
               )

        assert send_event(view, "rename_collection", %{
                 "id" => collection.id,
                 "rawName" => new_collection_name
               }) =~ "Collection updated"

        assert_ok(view)

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

        view = open(conn, project, "settings#collections")

        send_event(view, "delete_collection", %{"id" => collection.id})
        assert_refused(view)

        assert Repo.reload(collection)
      end
    end

    test "authorized users can delete a collection successfully", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:owner, :admin]) do
        collection = insert(:collection, project: project)

        view = open(conn, project, "settings#collections")

        assert send_event(view, "delete_collection", %{"id" => collection.id}) =~
                 "Collection deleted"

        assert_ok(view)

        # collection does not exist
        refute Lightning.Repo.get(
                 Lightning.Collections.Collection,
                 collection.id
               )

        refute Enum.any?(
                 props(view)["collections"]["collections"],
                 &(&1["id"] == collection.id)
               )
      end
    end

    test "every collection of the project is listed", %{
      conn: conn,
      user: user
    } do
      project = insert(:project)
      insert(:project_user, role: :owner, project: project, user: user)

      collection_a = insert(:collection, project: project)
      collection_b = insert(:collection, project: project)
      insert(:collection, project: insert(:project))

      ids =
        conn
        |> open(project, "settings#collections")
        |> props()
        |> get_in(["collections", "collections"])
        |> Enum.map(& &1["id"])

      assert Enum.sort(ids) == Enum.sort([collection_a.id, collection_b.id])
    end

    test "preview replies the first item's key and value", %{
      conn: conn,
      user: user
    } do
      project = insert(:project)
      insert(:project_user, role: :owner, project: project, user: user)
      collection = insert(:collection, project: project)

      insert(:collection_item,
        collection: collection,
        key: "my-key",
        value: "my-value"
      )

      view = open(conn, project, "settings#collections")

      send_event(view, "preview_collection", %{"id" => collection.id})
      assert_reply(view, %{record: record})

      assert [%{"key" => "my-key", "value" => "my-value"}] =
               Jason.decode!(record)
    end

    test "preview of an empty collection replies no record", %{
      conn: conn,
      user: user
    } do
      project = insert(:project)
      insert(:project_user, role: :owner, project: project, user: user)
      collection = insert(:collection, project: project)

      view = open(conn, project, "settings#collections")

      send_event(view, "preview_collection", %{"id" => collection.id})
      assert_reply(view, %{record: nil})
    end

    test "all project members can preview a collection", %{conn: conn} do
      project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        collection = insert(:collection, project: project)
        insert(:collection_item, collection: collection, key: "visible")

        view = open(conn, project, "settings#collections")

        send_event(view, "preview_collection", %{"id" => collection.id})
        assert_reply(view, %{record: record})
        assert [%{"key" => "visible"}] = Jason.decode!(record)
      end
    end

    test "cannot preview a collection belonging to another project", %{
      conn: conn,
      user: user
    } do
      their_project = insert(:project)
      insert(:project_user, role: :owner, project: their_project, user: user)

      other_project = insert(:project)
      other_collection = insert(:collection, project: other_project)
      insert(:collection_item, collection: other_collection)

      view = open(conn, their_project, "settings#collections")

      send_event(view, "preview_collection", %{"id" => other_collection.id})
      assert_reply(view, %{error: "Collection not found"})
    end

    test "cannot edit a collection belonging to another project", %{
      conn: conn,
      user: user
    } do
      their_project = insert(:project)
      insert(:project_user, role: :owner, project: their_project, user: user)

      other_project = insert(:project)
      other_collection = insert(:collection, project: other_project)

      view = open(conn, their_project, "settings#collections")

      send_event(view, "rename_collection", %{
        "id" => other_collection.id,
        "rawName" => "renamed"
      })

      assert_reply(view, %{error: "Collection not found"})
      assert Repo.reload(other_collection).name == other_collection.name
    end

    test "cannot delete a collection belonging to another project", %{
      conn: conn,
      user: user
    } do
      their_project = insert(:project)
      insert(:project_user, role: :owner, project: their_project, user: user)

      other_project = insert(:project)
      other_collection = insert(:collection, project: other_project)

      view = open(conn, their_project, "settings#collections")

      send_event(view, "delete_collection", %{"id" => other_collection.id})
      assert_reply(view, %{error: "Collection not found"})
      assert Repo.reload(other_collection)
    end

    test "collections are listed by name with their used storage", %{
      conn: conn
    } do
      project = insert(:project)
      [{conn, _user} | _] = setup_project_users(conn, project, [:owner])

      insert(:collection,
        project: project,
        name: "Charlie",
        byte_size_sum: 100
      )

      insert(:collection,
        project: project,
        name: "Alpha",
        byte_size_sum: 5_000_000_000
      )

      insert(:collection,
        project: project,
        name: "Bravo",
        byte_size_sum: 2_500_000
      )

      # The page sorts them and formats the sizes.
      assert [
               %{"name" => "Alpha", "byteSizeSum" => 5_000_000_000},
               %{"name" => "Bravo", "byteSizeSum" => 2_500_000},
               %{"name" => "Charlie", "byteSizeSum" => 100}
             ] =
               conn
               |> open(project, "settings#collections")
               |> props()
               |> get_in(["collections", "collections"])
    end
  end

  # Sends `event` for a project user in another project: the server refuses
  # it and the field is left as it was.
  defp assert_cross_project_pref_refused(conn, event, {key, value}, field, seed) do
    project_a = insert(:project)
    {conn, _admin} = setup_project_user(conn, project_a, :admin)

    other =
      insert(
        :project_user,
        [project: insert(:project), user: build(:user)] ++ [{field, seed}]
      )

    view = open(conn, project_a)

    send_event(view, event, %{"id" => other.id, key => value})
    assert_refused(view)
    assert Map.fetch!(Repo.reload(other), field) == seed
  end

  defp find_selected_option(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Enum.map(&Floki.raw_html/1)
    |> Enum.find(fn el -> el =~ "selected=\"true\"" end)
  end
end
