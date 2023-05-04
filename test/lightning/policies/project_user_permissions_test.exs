defmodule Lightning.ProjectUserPermissionsTest do
  @moduledoc """
  Project user permissions determine what a user can and cannot do within a
  project. Projects (i.e., "workspaces") can have multiple collaborators with
  varying levels of access to the resources (workflows, jobs, triggers, runs)
  within.

  Description of the level of access in a project:
  - viewer is the level 0, it's the lowest access level.
    It allows actions like accessing the resources of the project in read only
    mode and editing their own membership configurations (i.e digest alerts, failure alerts)
  - editor is the level 1. It allows actions like accessing the resources in read / write mode.
    Project members with editor access level can do what project members with viewer role can do and more.
    They can create / edit / delete / run / rerun jobs and create workflows
  - admin is the level 2. It allows administration access to project members.
    Admins of a project can do what editors can do and more. They can edit the project name and description
    and also add new project members to the project (collaborators).
  - owner is the level 3 and the highest level of access in a project. Owners are the creators of project.
    They can do what all other levels can do and more. Owners can delete projects.

  The tests ensure both that user "Amy" that has been added as an `editor` for project "X",
  _can_ view and edit jobs (for example) in project X, and that they _cannot_ view and edit jobs in project Y.
  """
  use Lightning.DataCase, async: true

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  alias Lightning.Accounts
  alias Lightning.Policies.{Permissions, ProjectUsers}

  setup do
    viewer = user_fixture()
    admin = user_fixture()
    owner = user_fixture()
    editor = user_fixture()
    intruder = user_fixture()

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

    test "can edit their own digest and failure alerts for that project",
         %{project: project} do
      project_user_1 = project.project_users |> Enum.at(0)

      user_1 = Accounts.get_user!(project_user_1.user_id)

      assert ProjectUsers
             |> Permissions.can?(
               :edit_digest_alerts,
               user_1,
               project_user_1
             )

      assert ProjectUsers
             |> Permissions.can?(
               :edit_failure_alerts,
               user_1,
               project_user_1
             )
    end

    test "cannot edit other members digest and failure alerts",
         %{project: project} do
      project_user_1 = project.project_users |> Enum.at(0)
      project_user_2 = project.project_users |> Enum.at(1)

      user_1 = Accounts.get_user!(project_user_1.user_id)

      refute ProjectUsers
             |> Permissions.can?(
               :edit_digest_alerts,
               user_1,
               project_user_2
             )

      refute ProjectUsers
             |> Permissions.can?(
               :edit_failure_alerts,
               user_1,
               project_user_2
             )
    end
  end

  describe "Project users with the :viewer role" do
    test "cannot create workflows, create/edit/delete/run/rerun jobs, delete the project, and edit the project name or description",
         %{
           project: project,
           viewer: viewer
         } do
      refute ProjectUsers |> Permissions.can?(:run_job, viewer, project)
      refute ProjectUsers |> Permissions.can?(:edit_job, viewer, project)
      refute ProjectUsers |> Permissions.can?(:rerun_job, viewer, project)
      refute ProjectUsers |> Permissions.can?(:create_job, viewer, project)
      refute ProjectUsers |> Permissions.can?(:delete_job, viewer, project)
      refute ProjectUsers |> Permissions.can?(:delete_project, viewer, project)
      refute ProjectUsers |> Permissions.can?(:create_workflow, viewer, project)

      refute ProjectUsers
             |> Permissions.can?(:edit_project_name, viewer, project)

      refute ProjectUsers
             |> Permissions.can?(:edit_project_description, viewer, project)

      refute ProjectUsers
             |> Permissions.can?(:add_project_collaborator, viewer, project)
    end
  end

  describe "Project users with the :editor role" do
    test "can create workflows and edit/create/delete/run/rerun jobs in the project",
         %{
           project: project,
           editor: editor
         } do
      assert ProjectUsers |> Permissions.can?(:run_job, editor, project)
      assert ProjectUsers |> Permissions.can?(:edit_job, editor, project)
      assert ProjectUsers |> Permissions.can?(:rerun_job, editor, project)
      assert ProjectUsers |> Permissions.can?(:create_job, editor, project)
      assert ProjectUsers |> Permissions.can?(:delete_job, editor, project)
      assert ProjectUsers |> Permissions.can?(:create_workflow, editor, project)
    end

    test "cannot delete the project, edit the project name, and edit the project description",
         %{
           project: project,
           editor: editor
         } do
      refute ProjectUsers |> Permissions.can?(:delete_project, editor, project)

      refute ProjectUsers
             |> Permissions.can?(:edit_project_name, editor, project)

      refute ProjectUsers
             |> Permissions.can?(:edit_project_description, editor, project)

      refute ProjectUsers
             |> Permissions.can?(:add_project_collaborator, editor, project)
    end
  end

  describe "Project users with the :admin role" do
    test "can do what editors can do, and edit the project name, edit the project description, and add collaborators to the project",
         %{
           project: project,
           admin: admin
         } do
      assert ProjectUsers |> Permissions.can?(:edit_project_name, admin, project)

      assert ProjectUsers
             |> Permissions.can?(:edit_project_description, admin, project)

      assert ProjectUsers
             |> Permissions.can?(:add_project_collaborator, admin, project)
    end

    test "cannot delete the project", %{project: project, admin: admin} do
      refute ProjectUsers |> Permissions.can?(:delete_project, admin, project)
    end
  end

  describe "Project users with the :owner role" do
    test "can do what admins can do, and delete the project", %{
      project: project,
      owner: owner
    } do
      assert ProjectUsers |> Permissions.can?(:delete_project, owner, project)
    end
  end
end
