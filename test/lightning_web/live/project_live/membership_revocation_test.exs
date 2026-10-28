defmodule LightningWeb.ProjectLive.MembershipRevocationTest do
  @moduledoc """
  Session teardown for project-scoped LiveViews.
  """
  use LightningWeb.ConnCase, async: true

  import Ecto.Changeset, only: [change: 2]
  import Lightning.Factories
  import Lightning.ProjectsHelpers
  import LightningWeb.ProjectSettingsPageHelpers
  import Phoenix.LiveViewTest

  alias Lightning.Projects
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo

  # The broadcast lands in the victim's mailbox synchronously, but the teardown
  # is asynchronous relative to the test process.
  @teardown_timeout 2_000

  setup %{conn: conn} do
    admin = insert(:user, first_name: "Ada", last_name: "Admin")
    owner = insert(:user, first_name: "Olga", last_name: "Owner")
    other = insert(:user, first_name: "Eli", last_name: "Editor")
    superuser = insert(:user, role: :superuser)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: other, role: :editor}
        ]
      )

    %{
      conn: log_in_user(conn, admin),
      project: project,
      admin: admin,
      admin_project_user: Projects.get_project_user(project, admin),
      owner: owner,
      other: other,
      other_project_user: Projects.get_project_user(project, other),
      superuser: superuser
    }
  end

  describe "removal driven from the owner's settings LiveView" do
    test "kills the victim's settings socket and bounces a fresh mount", %{
      conn: conn,
      project: project,
      owner: owner,
      admin_project_user: admin_project_user
    } do
      {:ok, victim, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      monitor_ref = Process.monitor(victim.pid)

      remove_collaborator(owner, project, admin_project_user)

      assert_redirect(
        victim,
        ~p"/projects/#{project}/settings",
        @teardown_timeout
      )

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason},
                     @teardown_timeout

      refute Process.alive?(victim.pid)

      assert {:error,
              {:redirect, %{to: "/projects", flash: %{"nav" => :not_found}}}} =
               live(conn, ~p"/projects/#{project}/settings")
    end

    test "kills the victim's history socket too", %{
      conn: conn,
      project: project,
      owner: owner,
      admin_project_user: admin_project_user
    } do
      {:ok, victim, _html} =
        live(conn, ~p"/projects/#{project}/history", on_error: :raise)

      # Let the LiveView's `start_async` work order load settle: killing the
      # view mid-query would tear down this test's sandbox connection.
      render_async(victim)

      monitor_ref = Process.monitor(victim.pid)

      remove_collaborator(owner, project, admin_project_user)

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason},
                     @teardown_timeout

      assert {:error, {:redirect, %{to: "/projects"}}} =
               live(conn, ~p"/projects/#{project}/history")
    end

    test "removing somebody else leaves the victim mounted", %{
      conn: conn,
      project: project,
      owner: owner,
      other_project_user: other_project_user
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      remove_collaborator(owner, project, other_project_user)

      assert props(view)["collaboration"]["canAddProjectUser"]
    end

    test "rejects a removal from an admin demoted after mount", %{
      conn: conn,
      project: project,
      admin: admin,
      other_project_user: other_project_user
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      # Demote without broadcasting, so the socket keeps its mount-time assigns
      # exactly as it would in the race this guards.
      project
      |> Projects.get_project_user(admin)
      |> change(role: :editor)
      |> Repo.update!()

      send_event(view, "remove_collaborator", %{
        "id" => other_project_user.id
      })

      assert_refused(view)

      assert Repo.get(ProjectUser, other_project_user.id)
    end
  end

  describe "role change driven from the superuser project form" do
    test "kills the victim's socket and the re-mount drops admin controls", %{
      conn: conn,
      project: project,
      admin: admin,
      superuser: superuser
    } do
      {:ok, victim, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert %{
               "collaboration" => %{"canAddProjectUser" => true},
               "setup" => %{"canEditProject" => true}
             } = props(victim)

      monitor_ref = Process.monitor(victim.pid)

      set_role_via_form(superuser, project, admin, "editor")

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason},
                     @teardown_timeout

      {:ok, remounted, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      assert %{
               "collaboration" => %{"canAddProjectUser" => false},
               "setup" => %{"canEditProject" => false}
             } = props(remounted)
    end
  end

  describe "being added to a project I already hold a session on" do
    test "re-mounts the support user's socket", %{owner: owner} do
      # A support user holds a session on a project they are not a member of,
      # so they are the one client that can observe their own addition.
      support_user = insert(:user, role: :superuser, support_user: true)

      project =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: owner, role: :owner}]
        )

      {:ok, view, _html} =
        live(user_conn(support_user), ~p"/projects/#{project}/settings",
          on_error: :raise
        )

      monitor_ref = Process.monitor(view.pid)

      {:ok, _project_users} =
        Projects.add_project_users(
          project,
          [%{user_id: support_user.id, role: :viewer}],
          owner,
          false
        )

      assert_redirect(
        view,
        ~p"/projects/#{project}/settings",
        @teardown_timeout
      )

      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason},
                     @teardown_timeout
    end
  end

  describe "adding a collaborator from a socket demoted after mount" do
    test "refuses visibly and adds nobody", %{
      conn: conn,
      project: project,
      admin: admin
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      # Demote without broadcasting: the click below is one the user had already
      # queued when the teardown they never received would have fired.
      project
      |> Projects.get_project_user(admin)
      |> change(role: :viewer)
      |> Repo.update!()

      newcomer = insert(:user)

      send_event(view, "add_collaborators", %{
        "collaborators" => [%{"email" => newcomer.email, "role" => "editor"}]
      })

      assert_refused(view)

      assert project
             |> Repo.preload(:project_users, force: true)
             |> Map.fetch!(:project_users)
             |> length() == 3
    end
  end

  describe "project settings changes from a socket demoted after mount" do
    setup %{conn: conn, project: project, admin: admin} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings", on_error: :raise)

      # Demote without broadcasting: every event below is one the user had
      # already queued when the teardown they never received would have fired,
      # so the socket still carries the assigns it was mounted with.
      project
      |> Projects.get_project_user(admin)
      |> change(role: :viewer)
      |> Repo.update!()

      %{view: view}
    end

    test "refuses a rename", %{project: project, view: view} do
      send_event(view, "save_identity", %{
        "rawName" => "renamed-by-a-viewer"
      })

      assert_refused(view)

      assert Repo.reload!(project).name == project.name
    end

    test "refuses a support-access toggle", %{project: project, view: view} do
      send_event(view, "set_support_access", %{"on" => true})
      assert_refused(view)

      refute Repo.reload!(project).allow_support_access
    end

    test "refuses an MFA toggle", %{project: project, view: view} do
      send_event(view, "set_requires_mfa", %{"on" => true})
      assert_refused(view)

      refute Repo.reload!(project).requires_mfa
    end

    test "refuses a retention-policy change", %{project: project, view: view} do
      send_event(view, "save_data_storage", %{
        "retentionPolicy" => "erase_all"
      })

      assert_refused(view)

      assert Repo.reload!(project).retention_policy == project.retention_policy
    end
  end

  describe "re-mount path" do
    test "keeps the query string the user was looking at", %{
      conn: conn,
      project: project,
      admin: admin,
      owner: owner
    } do
      path = ~p"/projects/#{project}/history?filters[success]=true"

      {:ok, victim, _html} = live(conn, path, on_error: :raise)

      render_async(victim)

      set_role_via_context(project, admin, :editor, owner)

      assert_redirect(victim, path, @teardown_timeout)
    end
  end

  defp remove_collaborator(owner, project, project_user) do
    {:ok, owner_view, _html} =
      live(user_conn(owner), ~p"/projects/#{project}/settings", on_error: :raise)

    Mox.allow(LightningMock, self(), owner_view.pid)

    send_event(owner_view, "remove_collaborator", %{
      "id" => project_user.id
    })

    assert_ok(owner_view)

    refute Repo.get(ProjectUser, project_user.id)
  end

  defp set_role_via_form(superuser, project, user, role) do
    {:ok, form_view, _html} =
      live(user_conn(superuser), ~p"/settings/projects/#{project.id}",
        on_error: :raise
      )

    Mox.allow(LightningMock, self(), form_view.pid)

    # The page sends a role per user; the rest keep theirs.
    roles =
      page_props(form_view, "#admin-projects-page")["form"]["project"]["members"]
      |> Map.new(&{&1["userId"], &1["role"]})
      |> Map.put(user.id, role)

    push_page_event(form_view, "#admin-projects-page", "save_project", %{
      "rawName" => project.name,
      "roles" => roles
    })

    assert Repo.get_by(ProjectUser, project_id: project.id, user_id: user.id).role ==
             String.to_existing_atom(role)
  end

  defp set_role_via_context(project, user, role, actor) do
    {project, params} = membership_params(project, %{user => role})

    {:ok, _project} =
      Projects.update_project_with_users(project, params, actor, false)
  end
end
