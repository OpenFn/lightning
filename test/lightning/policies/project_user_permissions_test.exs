defmodule Lightning.Policies.ProjectUserPermissionsTest do
  @moduledoc """
  Project user permissions determine what a user can and cannot do within a
  project. Projects (i.e., "workspaces") can have multiple collaborators with
  varying levels of access to the resources (workflows, jobs, triggers, runs)
  within.

  The tests ensure both that user "Amy" that has been added as an `editor` for project "X",
  _can_ view and edit jobs (for example) in project X, and that they _cannot_ view and edit jobs in project Y.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Accounts
  alias Lightning.Policies.{Permissions, ProjectUsers}

  setup do
    viewer = insert(:user)
    admin = insert(:user)
    owner = insert(:user)
    editor = insert(:user)
    intruder = insert(:user)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    project =
      insert(:project,
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ]
      )

    marked_project =
      insert(:project,
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ],
        scheduled_deletion: now
      )

    %{
      project: project,
      marked_project: marked_project,
      viewer: viewer,
      admin: admin,
      owner: owner,
      editor: editor,
      intruder: intruder
    }
  end

  describe "Users that are not members to a project" do
    test "cannot access that project", %{project: project, intruder: intruder} do
      refute ProjectUsers |> Permissions.can?(:access_project, intruder, project)
    end
  end

  describe "Members of a project (viewer, editor, admin or owner)" do
    test "can access that project", %{
      project: project,
      viewer: viewer
    } do
      assert ProjectUsers |> Permissions.can?(:access_project, viewer, project)
    end

    test "can not access a project that is scheduled for deletion", %{
      marked_project: marked_project,
      viewer: viewer
    } do
      refute ProjectUsers
             |> Permissions.can?(:access_project, viewer, marked_project)
    end

    test "can edit their own digest and failure alerts for that project",
         %{project: project} do
      project_user_1 = project.project_users |> Enum.at(0)
      user_1 = Accounts.get_user!(project_user_1.user_id)

      ~w(
        edit_digest_alerts
        edit_failure_alerts
      )a |> (&assert_can(ProjectUsers, &1, user_1, project_user_1)).()
    end

    test "cannot edit other members digest and failure alerts",
         %{project: project} do
      project_user_1 = project.project_users |> Enum.at(0)
      project_user_2 = project.project_users |> Enum.at(1)
      user_1 = Accounts.get_user!(project_user_1.user_id)

      ~w(
        edit_digest_alerts
        edit_failure_alerts
      )a |> (&refute_can(ProjectUsers, &1, user_1, project_user_2)).()
    end
  end

  describe "Project users with the :viewer role" do
    test "cannot create / delete workflows, create / edit / run / rerun jobs, and edit the project name or description",
         %{
           project: project,
           viewer: viewer
         } do
      ~w(
        create_workflow
        delete_workflow
        edit_workflow
        edit_project
        write_webhook_auth_method
        create_project_credential
        run_workflow
      )a |> (&refute_can(ProjectUsers, &1, viewer, project)).()
    end
  end

  describe "Project users with the :editor role" do
    test "can create / delete workflows and create / edit / run / rerun jobs in the project",
         %{
           project: project,
           editor: editor
         } do
      ~w(
        create_workflow
        delete_workflow
        edit_workflow
        create_project_credential
        run_workflow
      )a |> (&assert_can(ProjectUsers, &1, editor, project)).()
    end

    test "cannot edit the project name, and edit the project description",
         %{
           project: project,
           editor: editor
         } do
      ~w(
          edit_project
          write_webhook_auth_method
        )a |> (&refute_can(ProjectUsers, &1, editor, project)).()
    end
  end

  describe "Project users with the :admin role" do
    test "can create / delete workflows, create / edit / run / rerun jobs, edit the project name, and edit the project description.",
         %{
           project: project,
           admin: admin
         } do
      ~w(
          create_workflow
          delete_workflow
          edit_workflow
          edit_project
          write_webhook_auth_method
          create_project_credential
          run_workflow
        )a |> (&assert_can(ProjectUsers, &1, admin, project)).()
    end
  end

  describe "Project users with the :owner role" do
    test "can create / delete workflows, create / edit / run / rerun jobs, edit the project name, and edit the project description.",
         %{
           project: project,
           owner: owner
         } do
      ~w(
        create_workflow
        delete_workflow
        edit_workflow
        edit_project
        write_webhook_auth_method
        create_project_credential
        run_workflow
      )a |> (&assert_can(ProjectUsers, &1, owner, project)).()
    end
  end

  describe "Support users" do
    test "can access projects that allow support access", %{project: project} do
      support_user = insert(:user, support_user: true)
      project = %{project | allow_support_access: true}

      assert ProjectUsers
             |> Permissions.can?(:access_project, support_user, project)
    end

    test "cannot access projects that don't allow support access", %{
      project: project
    } do
      support_user = insert(:user, support_user: true)
      project = %{project | allow_support_access: false}

      refute ProjectUsers
             |> Permissions.can?(:access_project, support_user, project)
    end

    test "have the same worfklow allowance as editor", %{project: project} do
      support_user = insert(:user, support_user: true)

      editor_project_user =
        insert(:project_user,
          project: project,
          user: build(:user),
          role: :editor
        )

      ~w(
        create_workflow
        edit_workflow
        delete_workflow
        run_workflow
        create_project_credential
        initiate_github_sync
      )a |> (&assert_can(ProjectUsers, &1, support_user, nil)).()

      ~w(
        create_workflow
        edit_workflow
        delete_workflow
        run_workflow
        create_project_credential
        initiate_github_sync
      )a
      |> (&assert_can(
            ProjectUsers,
            &1,
            editor_project_user.user,
            editor_project_user
          )).()
    end

    test "cannot perform project user actions when not a support user", %{
      project: _project
    } do
      regular_user = insert(:user, support_user: false)

      ~w(
        create_workflow
        edit_workflow
        delete_workflow
        run_workflow
        create_project_credential
        initiate_github_sync
      )a |> (&refute_can(ProjectUsers, &1, regular_user, nil)).()
    end
  end

  defp assert_can(module, actions, user, subject) when is_list(actions) do
    Enum.each(actions, &assert_can(module, &1, user, subject))
  end

  defp assert_can(module, action, user, subject) when is_atom(action) do
    assert module |> Permissions.can?(action, user, subject)
  end

  defp refute_can(module, actions, user, subject) when is_list(actions) do
    Enum.each(actions, &refute_can(module, &1, user, subject))
  end

  defp refute_can(module, action, user, subject) when is_atom(action) do
    refute module |> Permissions.can?(action, user, subject)
  end
end
