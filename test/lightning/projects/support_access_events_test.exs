defmodule Lightning.Projects.SupportAccessEventsTest do
  use Lightning.DataCase, async: true

  import Lightning.ProjectsHelpers

  alias Lightning.Projects
  alias Lightning.Projects.Events
  alias Lightning.Projects.Events.SupportAccessUpdated

  setup do
    owner = insert(:user)
    member = insert(:user)

    project =
      insert(:project,
        allow_support_access: true,
        project_users: [
          %{user_id: owner.id, role: :owner},
          %{user_id: member.id, role: :editor}
        ]
      )

    assert :ok = Events.subscribe(project.id)

    %{project: project, owner: owner, member: member}
  end

  describe "update_project/3" do
    test "broadcasts the flag's new value in both directions", %{
      project: %{id: project_id} = project,
      owner: owner
    } do
      assert {:ok, revoked} =
               Projects.update_project(
                 project,
                 %{allow_support_access: false},
                 owner
               )

      assert_receive %SupportAccessUpdated{
        project_id: ^project_id,
        allowed: false
      }

      assert {:ok, _granted} =
               Projects.update_project(
                 revoked,
                 %{allow_support_access: true},
                 owner
               )

      assert_receive %SupportAccessUpdated{
        project_id: ^project_id,
        allowed: true
      }
    end

    test "broadcasts nothing for an update that leaves the flag alone", %{
      project: project,
      owner: owner
    } do
      assert {:ok, _project} =
               Projects.update_project(
                 project,
                 %{description: "Now with a description"},
                 owner
               )

      refute_receive %SupportAccessUpdated{}
    end

    test "broadcasts nothing when the flag is resubmitted unchanged", %{
      project: project,
      owner: owner
    } do
      assert {:ok, _project} =
               Projects.update_project(
                 project,
                 %{allow_support_access: true},
                 owner
               )

      refute_receive %SupportAccessUpdated{}
    end

    test "broadcasts nothing when the update is rejected", %{
      project: project,
      owner: owner
    } do
      assert {:error, _changeset} =
               Projects.update_project(
                 project,
                 %{allow_support_access: false, name: "Not A Valid Name!"},
                 owner
               )

      refute_receive %SupportAccessUpdated{}

      assert Repo.reload!(project).allow_support_access
    end
  end

  describe "update_project_with_users/4" do
    test "broadcasts the flag change alongside the membership changes", %{
      project: %{id: project_id} = project,
      owner: owner,
      member: %{id: member_id} = member
    } do
      {project, params} = membership_params(project, %{member => :viewer})

      assert {:ok, _project} =
               Projects.update_project_with_users(
                 project,
                 Map.put(params, :allow_support_access, false),
                 owner,
                 false
               )

      assert_receive %SupportAccessUpdated{
        project_id: ^project_id,
        allowed: false
      }

      assert_receive %Events.ProjectUserRoleChanged{
        project_id: ^project_id,
        user_id: ^member_id
      }
    end

    test "broadcasts nothing when only membership changes", %{
      project: %{id: project_id} = project,
      owner: owner,
      member: %{id: member_id} = member
    } do
      {project, params} = membership_params(project, %{member => :admin})

      assert {:ok, _project} =
               Projects.update_project_with_users(project, params, owner, false)

      assert_receive %Events.ProjectUserRoleChanged{
        project_id: ^project_id,
        user_id: ^member_id
      }

      refute_received %SupportAccessUpdated{}
    end
  end
end
