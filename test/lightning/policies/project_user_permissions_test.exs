defmodule Lightning.ProjectUserPermissionsTest do
  @moduledoc """
  Project user permissions determine what a user can and cannot do within a
  project. Projects (i.e., "workspaces") can have multiple collaborators with
  varying levels of access to the resources (workflows, jobs, triggers, runs)
  within.

  The tests ensure both that user "Amy" that has been added as an `editor` for
  project "X", via the creation of a

    %ProjectUser{ user: "Amy", role: "editor", project: "X"}

  _can_ view and edit jobs (for example) in project X, and that they _cannot_
  view and edit jobs in project Y.
  """
  use Lightning.DataCase, async: true

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  alias Lightning.Policies.{Permissions, ProjectUsers}

  setup do
    viewer = user_fixture()
    admin = user_fixture()
    owner = user_fixture()
    editor = user_fixture()
    thief = user_fixture()

    project =
      project_fixture(
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ]
      )

    %{
      project: project,
      viewer: viewer,
      admin: admin,
      owner: owner,
      editor: editor,
      thief: thief
    }
  end

  describe "Project users with the :viewer role" do
    test "can see but not edit resources", %{project: project, viewer: viewer} do
      refute ProjectUsers |> Permissions.can(:create_workflow, viewer, project)
      refute ProjectUsers |> Permissions.can(:edit_job, viewer, project)
      refute ProjectUsers |> Permissions.can(:create_job, viewer, project)
      refute ProjectUsers |> Permissions.can(:delete_job, viewer, project)
      refute ProjectUsers |> Permissions.can(:run_job, viewer, project)
      refute ProjectUsers |> Permissions.can(:rerun_job, viewer, project)

      assert ProjectUsers
             |> Permissions.can(:view_last_job_inputs, viewer, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_input, viewer, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_run, viewer, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_history, viewer, project)

      assert ProjectUsers |> Permissions.can(:view_project_name, viewer, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_description, viewer, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_credentials, viewer, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_collaborators, viewer, project)

      refute ProjectUsers |> Permissions.can(:delete_project, viewer, project)

      assert ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               viewer,
               project.project_users |> Enum.at(0)
             )

      refute ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               viewer,
               project.project_users |> Enum.at(1)
             )

      refute ProjectUsers |> Permissions.can(:edit_project_name, viewer, project)

      refute ProjectUsers
             |> Permissions.can(:edit_project_description, viewer, project)

      refute ProjectUsers
             |> Permissions.can(:add_project_collaborator, viewer, project)

      viewer_project_user = project.project_users |> Enum.at(0)
      editor_project_user = project.project_users |> Enum.at(1)

      assert ProjectUsers
             |> Permissions.can(:edit_project_user, viewer, viewer_project_user)

      refute ProjectUsers
             |> Permissions.can(:edit_project_user, viewer, editor_project_user)
    end
  end

  describe "Project users with the :editor role" do
    test "can edit resources in their project", %{
      project: project,
      editor: editor
    } do
      assert ProjectUsers |> Permissions.can(:create_workflow, editor, project)
      assert ProjectUsers |> Permissions.can(:edit_job, editor, project)
      assert ProjectUsers |> Permissions.can(:create_job, editor, project)
      assert ProjectUsers |> Permissions.can(:delete_job, editor, project)
      assert ProjectUsers |> Permissions.can(:run_job, editor, project)
      assert ProjectUsers |> Permissions.can(:rerun_job, editor, project)

      assert ProjectUsers
             |> Permissions.can(:view_last_job_inputs, editor, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_input, editor, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_run, editor, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_history, editor, project)

      assert ProjectUsers |> Permissions.can(:view_project_name, editor, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_description, editor, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_credentials, editor, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_collaborators, editor, project)

      refute ProjectUsers |> Permissions.can(:delete_project, editor, project)

      assert ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               editor,
               project.project_users |> Enum.at(1)
             )

      refute ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               editor,
               project.project_users |> Enum.at(0)
             )

      refute ProjectUsers |> Permissions.can(:edit_project_name, editor, project)

      refute ProjectUsers
             |> Permissions.can(:edit_project_description, editor, project)

      refute ProjectUsers
             |> Permissions.can(:add_project_collaborator, editor, project)

      viewer_project_user = project.project_users |> Enum.at(0)
      editor_project_user = project.project_users |> Enum.at(1)

      assert ProjectUsers
             |> Permissions.can(:edit_project_user, editor, editor_project_user)

      refute ProjectUsers
             |> Permissions.can(:edit_project_user, editor, viewer_project_user)
    end
  end

  describe "Project users with the :admin role" do
    test "can do everything that editors can do, plus...", %{
      project: project,
      admin: admin
    } do
      assert ProjectUsers |> Permissions.can(:create_workflow, admin, project)
      assert ProjectUsers |> Permissions.can(:edit_job, admin, project)
      assert ProjectUsers |> Permissions.can(:create_job, admin, project)
      assert ProjectUsers |> Permissions.can(:delete_job, admin, project)
      assert ProjectUsers |> Permissions.can(:run_job, admin, project)
      assert ProjectUsers |> Permissions.can(:rerun_job, admin, project)

      assert ProjectUsers
             |> Permissions.can(:view_last_job_inputs, admin, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_input, admin, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_run, admin, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_history, admin, project)

      assert ProjectUsers |> Permissions.can(:view_project_name, admin, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_description, admin, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_credentials, admin, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_collaborators, admin, project)

      refute ProjectUsers |> Permissions.can(:delete_project, admin, project)

      assert ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               admin,
               project.project_users |> Enum.at(2)
             )

      refute ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               admin,
               project.project_users |> Enum.at(0)
             )

      assert ProjectUsers |> Permissions.can(:edit_project_name, admin, project)

      assert ProjectUsers
             |> Permissions.can(:edit_project_description, admin, project)

      assert ProjectUsers
             |> Permissions.can(:add_project_collaborator, admin, project)

      viewer_project_user = project.project_users |> Enum.at(0)
      admin_project_user = project.project_users |> Enum.at(2)

      assert ProjectUsers
             |> Permissions.can(:edit_project_user, admin, admin_project_user)

      refute ProjectUsers
             |> Permissions.can(:edit_project_user, admin, viewer_project_user)
    end
  end

  describe "Project users with the :owner role" do
    test "can do everything that admins can do, plus...", %{
      project: project,
      owner: owner
    } do
      assert ProjectUsers |> Permissions.can(:create_workflow, owner, project)
      assert ProjectUsers |> Permissions.can(:edit_job, owner, project)
      assert ProjectUsers |> Permissions.can(:create_job, owner, project)
      assert ProjectUsers |> Permissions.can(:delete_job, owner, project)
      assert ProjectUsers |> Permissions.can(:run_job, owner, project)
      assert ProjectUsers |> Permissions.can(:rerun_job, owner, project)

      assert ProjectUsers
             |> Permissions.can(:view_last_job_inputs, owner, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_input, owner, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_run, owner, project)

      assert ProjectUsers
             |> Permissions.can(:view_workorder_history, owner, project)

      assert ProjectUsers |> Permissions.can(:view_project_name, owner, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_description, owner, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_credentials, owner, project)

      assert ProjectUsers
             |> Permissions.can(:view_project_collaborators, owner, project)

      assert ProjectUsers |> Permissions.can(:delete_project, owner, project)

      assert ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               owner,
               project.project_users |> Enum.at(3)
             )

      refute ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               owner,
               project.project_users |> Enum.at(0)
             )

      assert ProjectUsers |> Permissions.can(:edit_project_name, owner, project)

      assert ProjectUsers
             |> Permissions.can(:edit_project_description, owner, project)

      assert ProjectUsers
             |> Permissions.can(:add_project_collaborator, owner, project)

      viewer_project_user = project.project_users |> Enum.at(0)
      owner_project_user = project.project_users |> Enum.at(3)

      assert ProjectUsers
             |> Permissions.can(:edit_project_user, owner, owner_project_user)

      refute ProjectUsers
             |> Permissions.can(:edit_project_user, owner, viewer_project_user)
    end
  end

  describe "Thieves (users without any project_user for a given project)" do
    # For things like :view_job we should be able to show that people who do not
    # have access to a project cannot view the jobs in that project.
    test "cannot view or modify anything...", %{project: project, thief: thief} do
      refute ProjectUsers |> Permissions.can(:create_workflow, thief, project)
      refute ProjectUsers |> Permissions.can(:create_job, thief, project)
      refute ProjectUsers |> Permissions.can(:delete_job, thief, project)
      refute ProjectUsers |> Permissions.can(:edit_job, thief, project)
      refute ProjectUsers |> Permissions.can(:run_job, thief, project)
      refute ProjectUsers |> Permissions.can(:rerun_job, thief, project)

      refute ProjectUsers
             |> Permissions.can(:view_last_job_inputs, thief, project)

      refute ProjectUsers
             |> Permissions.can(:view_workorder_input, thief, project)

      refute ProjectUsers
             |> Permissions.can(:view_workorder_run, thief, project)

      refute ProjectUsers
             |> Permissions.can(:view_workorder_history, thief, project)

      refute ProjectUsers |> Permissions.can(:view_project_name, thief, project)

      refute ProjectUsers
             |> Permissions.can(:view_project_description, thief, project)

      refute ProjectUsers
             |> Permissions.can(:view_project_credentials, thief, project)

      refute ProjectUsers
             |> Permissions.can(:view_project_collaborators, thief, project)

      refute ProjectUsers |> Permissions.can(:delete_project, thief, project)

      refute ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               thief,
               project.project_users |> Enum.at(3)
             )

      refute ProjectUsers
             |> Permissions.can(
               :edit_digest_alerts,
               thief,
               project.project_users |> Enum.at(0)
             )

      refute ProjectUsers |> Permissions.can(:edit_project_name, thief, project)

      refute ProjectUsers
             |> Permissions.can(:edit_project_description, thief, project)

      refute ProjectUsers
             |> Permissions.can(:add_project_collaborator, thief, project)
    end
  end
end
