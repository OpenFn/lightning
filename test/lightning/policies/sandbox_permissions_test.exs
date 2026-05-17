defmodule Lightning.Policies.SandboxesTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Sandboxes

  setup do
    superuser = insert(:user, role: :superuser)
    user = insert(:user)
    other_user = insert(:user)

    root_project = insert(:project)
    root_project_owner = insert(:user)

    insert(:project_user,
      user: root_project_owner,
      project: root_project,
      role: :owner
    )

    sandbox = insert(:sandbox, parent: root_project)

    sandbox_with_owner = insert(:sandbox, parent: root_project)
    sandbox_owner = insert(:user)

    insert(:project_user,
      user: sandbox_owner,
      project: sandbox_with_owner,
      role: :owner
    )

    sandbox_with_admin = insert(:sandbox, parent: root_project)
    sandbox_admin = insert(:user)

    insert(:project_user,
      user: sandbox_admin,
      project: sandbox_with_admin,
      role: :admin
    )

    other_root_project = insert(:project)
    other_sandbox = insert(:sandbox, parent: other_root_project)

    root_project = Lightning.Repo.preload(root_project, :project_users)
    sandbox = Lightning.Repo.preload(sandbox, :project_users)

    sandbox_with_owner =
      Lightning.Repo.preload(sandbox_with_owner, :project_users)

    sandbox_with_admin =
      Lightning.Repo.preload(sandbox_with_admin, :project_users)

    other_root_project =
      Lightning.Repo.preload(other_root_project, :project_users)

    other_sandbox = Lightning.Repo.preload(other_sandbox, :project_users)

    %{
      superuser: superuser,
      user: user,
      other_user: other_user,
      root_project: root_project,
      root_project_owner: root_project_owner,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner,
      sandbox_owner: sandbox_owner,
      sandbox_with_admin: sandbox_with_admin,
      sandbox_admin: sandbox_admin,
      other_root_project: other_root_project,
      other_sandbox: other_sandbox
    }
  end

  describe "provision_sandbox permissions" do
    test "owners on the parent project can provision sandboxes", %{
      root_project_owner: owner,
      root_project: root_project
    } do
      assert Sandboxes
             |> Permissions.can?(:provision_sandbox, owner, root_project)
    end

    test "admins on the parent project can provision sandboxes", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      assert Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)
    end

    test "editors on the parent project can provision sandboxes", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :editor)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      assert Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)
    end

    test "viewers on the parent project cannot provision sandboxes", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :viewer)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)
    end

    test "users with no role on the parent cannot provision sandboxes", %{
      user: user,
      root_project: root_project,
      other_root_project: other_root_project
    } do
      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)

      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, user, other_root_project)
    end

    test "superuser role alone does not grant provision authority", %{
      superuser: superuser,
      root_project: root_project
    } do
      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, superuser, root_project)
    end
  end

  describe "delete_sandbox permissions" do
    test "sandbox owners can delete their own sandbox", %{
      sandbox_owner: owner,
      sandbox_with_owner: sandbox
    } do
      assert Sandboxes |> Permissions.can?(:delete_sandbox, owner, sandbox)
    end

    test "sandbox admins can delete their sandbox", %{
      sandbox_admin: admin,
      sandbox_with_admin: sandbox
    } do
      assert Sandboxes |> Permissions.can?(:delete_sandbox, admin, sandbox)
    end

    test "regular users cannot delete sandboxes they don't own", %{
      user: user,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner,
      other_sandbox: other_sandbox
    } do
      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)

      refute Sandboxes
             |> Permissions.can?(:delete_sandbox, user, sandbox_with_owner)

      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, other_sandbox)
    end

    test "sandbox viewers cannot delete sandboxes", %{
      sandbox_with_owner: sandbox,
      user: user
    } do
      insert(:project_user, user: user, project: sandbox, role: :viewer)
      sandbox = Lightning.Repo.preload(sandbox, :project_users, force: true)
      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)
    end

    test "sandbox editors cannot delete sandboxes", %{
      sandbox: sandbox,
      user: user
    } do
      insert(:project_user, user: user, project: sandbox, role: :editor)
      sandbox = Lightning.Repo.preload(sandbox, :project_users, force: true)
      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)
    end

    test "role on the parent project does not grant delete authority on a sandbox",
         %{root_project: root_project, sandbox: sandbox, user: user} do
      insert(:project_user, user: user, project: root_project, role: :admin)

      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)
    end

    test "superuser role alone does not grant delete authority", %{
      superuser: superuser,
      sandbox: sandbox
    } do
      refute Sandboxes |> Permissions.can?(:delete_sandbox, superuser, sandbox)
    end
  end

  describe "update_sandbox permissions" do
    test "sandbox owners can update their own sandbox", %{
      sandbox_owner: owner,
      sandbox_with_owner: sandbox
    } do
      assert Sandboxes |> Permissions.can?(:update_sandbox, owner, sandbox)
    end

    test "sandbox admins can update their sandbox", %{
      sandbox_admin: admin,
      sandbox_with_admin: sandbox
    } do
      assert Sandboxes |> Permissions.can?(:update_sandbox, admin, sandbox)
    end

    test "regular users cannot update sandboxes they don't own", %{
      user: user,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner,
      other_sandbox: other_sandbox
    } do
      refute Sandboxes |> Permissions.can?(:update_sandbox, user, sandbox)

      refute Sandboxes
             |> Permissions.can?(:update_sandbox, user, sandbox_with_owner)

      refute Sandboxes |> Permissions.can?(:update_sandbox, user, other_sandbox)
    end

    test "sandbox viewers cannot update sandboxes", %{
      sandbox_with_owner: sandbox,
      user: user
    } do
      insert(:project_user, user: user, project: sandbox, role: :viewer)
      sandbox = Lightning.Repo.preload(sandbox, :project_users, force: true)
      refute Sandboxes |> Permissions.can?(:update_sandbox, user, sandbox)
    end

    test "role on the parent project does not grant update authority on a sandbox",
         %{root_project: root_project, sandbox: sandbox, user: user} do
      insert(:project_user, user: user, project: root_project, role: :admin)

      refute Sandboxes |> Permissions.can?(:update_sandbox, user, sandbox)
    end

    test "superuser role alone does not grant update authority", %{
      superuser: superuser,
      sandbox: sandbox
    } do
      refute Sandboxes |> Permissions.can?(:update_sandbox, superuser, sandbox)
    end
  end

  describe "merge_sandbox permissions" do
    test "editors on the target project can merge sandboxes", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :editor)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      assert Sandboxes
             |> Permissions.can?(:merge_sandbox, user, root_project)
    end

    test "admins on the target project can merge sandboxes", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      assert Sandboxes
             |> Permissions.can?(:merge_sandbox, user, root_project)
    end

    test "owners on the target project can merge sandboxes", %{
      root_project_owner: owner,
      root_project: root_project
    } do
      assert Sandboxes
             |> Permissions.can?(:merge_sandbox, owner, root_project)
    end

    test "viewers on the target project cannot merge sandboxes", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :viewer)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      refute Sandboxes
             |> Permissions.can?(:merge_sandbox, user, root_project)
    end

    test "users with no role on the target cannot merge sandboxes", %{
      root_project: root_project,
      user: user
    } do
      refute Sandboxes
             |> Permissions.can?(:merge_sandbox, user, root_project)
    end

    test "superuser role alone does not grant merge authority", %{
      superuser: superuser,
      root_project: root_project
    } do
      refute Sandboxes
             |> Permissions.can?(:merge_sandbox, superuser, root_project)
    end
  end

  describe "manage_authority/2 bulk operation" do
    setup %{
      root_project: root_project,
      sandbox: sandbox1,
      sandbox_with_owner: sandbox2,
      sandbox_with_admin: sandbox3
    } do
      sandbox4 = insert(:sandbox, parent: root_project)

      sandbox4 = Lightning.Repo.preload(sandbox4, :project_users)

      sandboxes = [sandbox1, sandbox2, sandbox3, sandbox4]

      %{sandboxes: sandboxes}
    end

    test "sandbox owner can manage their own sandbox and no others", %{
      sandbox_owner: owner,
      sandboxes: sandboxes,
      sandbox_with_owner: owned_sandbox
    } do
      authority = Sandboxes.manage_authority(sandboxes, owner)

      assert map_size(authority) == 4

      for sandbox <- sandboxes do
        expected = sandbox.id == owned_sandbox.id
        assert authority[sandbox.id] == expected
      end
    end

    test "sandbox admin can manage their own sandbox and no others", %{
      sandbox_admin: admin,
      sandboxes: sandboxes,
      sandbox_with_admin: admin_sandbox
    } do
      authority = Sandboxes.manage_authority(sandboxes, admin)

      for sandbox <- sandboxes do
        expected = sandbox.id == admin_sandbox.id
        assert authority[sandbox.id] == expected
      end
    end

    test "editor on a sandbox cannot manage it", %{
      sandboxes: sandboxes,
      sandbox: target_sandbox,
      user: user
    } do
      insert(:project_user, user: user, project: target_sandbox, role: :editor)

      target_sandbox =
        Lightning.Repo.preload(target_sandbox, :project_users, force: true)

      sandboxes =
        Enum.map(sandboxes, fn s ->
          if s.id == target_sandbox.id, do: target_sandbox, else: s
        end)

      authority = Sandboxes.manage_authority(sandboxes, user)

      for sandbox <- sandboxes do
        refute authority[sandbox.id]
      end
    end

    test "role on the root project does not cascade into manage authority over its sandboxes",
         %{
           root_project: root_project,
           sandboxes: sandboxes,
           user: user
         } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      authority = Sandboxes.manage_authority(sandboxes, user)

      for sandbox <- sandboxes do
        refute authority[sandbox.id]
      end
    end

    test "user with no role anywhere has no manage authority", %{
      user: user,
      sandboxes: sandboxes
    } do
      authority = Sandboxes.manage_authority(sandboxes, user)

      for sandbox <- sandboxes do
        refute authority[sandbox.id]
      end
    end

    test "superuser role alone does not grant manage authority", %{
      superuser: superuser,
      sandboxes: sandboxes
    } do
      authority = Sandboxes.manage_authority(sandboxes, superuser)

      for sandbox <- sandboxes do
        refute authority[sandbox.id]
      end
    end
  end

  describe "edge cases" do
    test "authorize returns false for unknown actions", %{
      user: user,
      sandbox: sandbox
    } do
      refute Sandboxes |> Permissions.can?(:unknown_action, user, sandbox)
    end

    test "authorize returns false for invalid parameters" do
      user = insert(:user)

      refute Sandboxes.authorize(:delete_sandbox, user, "not_a_project")
      refute Sandboxes.authorize(:update_sandbox, "not_a_user", insert(:project))
      refute Sandboxes.authorize(:provision_sandbox, nil, nil)
    end
  end
end
