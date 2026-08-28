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
    test "root project owners can provision sandboxes in their workspace", %{
      root_project_owner: owner,
      root_project: root_project
    } do
      assert Sandboxes
             |> Permissions.can?(:provision_sandbox, owner, root_project)
    end

    test "root project admins can provision sandboxes in their workspace", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      assert Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)
    end

    test "superusers without a project role cannot provision sandboxes", %{
      superuser: superuser,
      root_project: root_project,
      other_root_project: other_root_project
    } do
      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, superuser, root_project)

      refute Sandboxes
             |> Permissions.can?(
               :provision_sandbox,
               superuser,
               other_root_project
             )
    end

    test "regular project users cannot provision sandboxes", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :viewer)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)
    end

    test "users without project access cannot provision sandboxes", %{
      user: user,
      root_project: root_project,
      other_root_project: other_root_project
    } do
      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)

      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, user, other_root_project)
    end
  end

  describe "delete_sandbox permissions" do
    test "superusers without a project role cannot delete sandboxes", %{
      superuser: superuser,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner,
      other_sandbox: other_sandbox
    } do
      refute Sandboxes |> Permissions.can?(:delete_sandbox, superuser, sandbox)

      refute Sandboxes
             |> Permissions.can?(:delete_sandbox, superuser, sandbox_with_owner)

      refute Sandboxes
             |> Permissions.can?(:delete_sandbox, superuser, other_sandbox)
    end

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

    test "root project owners can delete any sandbox in their workspace", %{
      root_project_owner: owner,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner
    } do
      assert Sandboxes |> Permissions.can?(:delete_sandbox, owner, sandbox)

      assert Sandboxes
             |> Permissions.can?(:delete_sandbox, owner, sandbox_with_owner)
    end

    test "root project admins can delete any sandbox in their workspace", %{
      root_project: root_project,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      sandbox =
        Lightning.Repo.preload(sandbox, [parent: :project_users], force: true)

      sandbox_with_owner =
        Lightning.Repo.preload(sandbox_with_owner, [parent: :project_users],
          force: true
        )

      assert Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)

      assert Sandboxes
             |> Permissions.can?(:delete_sandbox, user, sandbox_with_owner)
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

    test "root project viewers cannot delete sandboxes in the workspace", %{
      root_project: root_project,
      sandbox: sandbox,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :viewer)

      sandbox =
        Lightning.Repo.preload(sandbox, [parent: :project_users], force: true)

      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)
    end
  end

  describe "update_sandbox permissions" do
    test "superusers without a project role cannot update sandboxes", %{
      superuser: superuser,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner,
      other_sandbox: other_sandbox
    } do
      refute Sandboxes |> Permissions.can?(:update_sandbox, superuser, sandbox)

      refute Sandboxes
             |> Permissions.can?(:update_sandbox, superuser, sandbox_with_owner)

      refute Sandboxes
             |> Permissions.can?(:update_sandbox, superuser, other_sandbox)
    end

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

    test "root project owners can update any sandbox in their workspace", %{
      root_project_owner: owner,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner
    } do
      assert Sandboxes |> Permissions.can?(:update_sandbox, owner, sandbox)

      assert Sandboxes
             |> Permissions.can?(:update_sandbox, owner, sandbox_with_owner)
    end

    test "root project admins can update any sandbox in their workspace", %{
      root_project: root_project,
      sandbox: sandbox,
      sandbox_with_owner: sandbox_with_owner,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      sandbox =
        Lightning.Repo.preload(sandbox, [parent: :project_users], force: true)

      sandbox_with_owner =
        Lightning.Repo.preload(sandbox_with_owner, [parent: :project_users],
          force: true
        )

      assert Sandboxes |> Permissions.can?(:update_sandbox, user, sandbox)

      assert Sandboxes
             |> Permissions.can?(:update_sandbox, user, sandbox_with_owner)
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

    test "root project viewers cannot update sandboxes in the workspace", %{
      root_project: root_project,
      sandbox: sandbox,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :viewer)

      sandbox =
        Lightning.Repo.preload(sandbox, [parent: :project_users], force: true)

      refute Sandboxes |> Permissions.can?(:update_sandbox, user, sandbox)
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

    test "users without project access cannot merge sandboxes", %{
      root_project: root_project,
      user: user
    } do
      refute Sandboxes
             |> Permissions.can?(:merge_sandbox, user, root_project)
    end

    test "superusers without a project role cannot merge sandboxes", %{
      superuser: superuser,
      root_project: root_project,
      other_root_project: other_root_project
    } do
      refute Sandboxes
             |> Permissions.can?(:merge_sandbox, superuser, root_project)

      refute Sandboxes
             |> Permissions.can?(
               :merge_sandbox,
               superuser,
               other_root_project
             )
    end
  end

  describe "check_manage_permissions/3 bulk operation" do
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

    test "superuser without a project role gets no manage rights", %{
      superuser: superuser,
      root_project: root_project,
      sandboxes: sandboxes
    } do
      permissions =
        Sandboxes.check_manage_permissions(sandboxes, superuser, root_project)

      assert map_size(permissions) == 4

      for sandbox <- sandboxes do
        assert permissions[sandbox.id] == false
      end
    end

    test "root project owner gets full permissions on all sandboxes in workspace",
         %{
           root_project_owner: owner,
           root_project: root_project,
           sandboxes: sandboxes
         } do
      permissions =
        Sandboxes.check_manage_permissions(sandboxes, owner, root_project)

      assert map_size(permissions) == 4

      for sandbox <- sandboxes do
        assert permissions[sandbox.id] == true
      end
    end

    test "root project admin gets full permissions on all sandboxes in workspace",
         %{
           root_project: root_project,
           sandboxes: sandboxes,
           user: user
         } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      permissions =
        Sandboxes.check_manage_permissions(sandboxes, user, root_project)

      assert map_size(permissions) == 4

      for sandbox <- sandboxes do
        assert permissions[sandbox.id] == true
      end
    end

    test "sandbox owner gets permissions only on their own sandbox", %{
      sandbox_owner: owner,
      root_project: root_project,
      sandboxes: sandboxes,
      sandbox_with_owner: owned_sandbox
    } do
      permissions =
        Sandboxes.check_manage_permissions(sandboxes, owner, root_project)

      assert map_size(permissions) == 4

      for sandbox <- sandboxes do
        if sandbox.id == owned_sandbox.id do
          assert permissions[sandbox.id] == true
        else
          assert permissions[sandbox.id] == false
        end
      end
    end

    test "sandbox admin gets permissions only on their own sandbox", %{
      sandbox_admin: admin,
      root_project: root_project,
      sandboxes: sandboxes,
      sandbox_with_admin: admin_sandbox
    } do
      permissions =
        Sandboxes.check_manage_permissions(sandboxes, admin, root_project)

      assert map_size(permissions) == 4

      for sandbox <- sandboxes do
        if sandbox.id == admin_sandbox.id do
          assert permissions[sandbox.id] == true
        else
          assert permissions[sandbox.id] == false
        end
      end
    end

    test "regular user gets no permissions on any sandbox", %{
      user: user,
      root_project: root_project,
      sandboxes: sandboxes
    } do
      permissions =
        Sandboxes.check_manage_permissions(sandboxes, user, root_project)

      assert map_size(permissions) == 4

      for sandbox <- sandboxes do
        assert permissions[sandbox.id] == false
      end
    end

    test "root project editor gets no manage rights without an admin/owner row on the sandbox",
         %{
           root_project: root_project,
           sandboxes: sandboxes,
           user: user
         } do
      insert(:project_user, user: user, project: root_project, role: :editor)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      permissions =
        Sandboxes.check_manage_permissions(sandboxes, user, root_project)

      assert map_size(permissions) == 4

      for sandbox <- sandboxes do
        assert permissions[sandbox.id] == false
      end
    end
  end

  describe "edge cases and private function coverage" do
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

    test "has_root_project_permission? private function coverage", %{
      root_project: root_project,
      user: user
    } do
      sandbox = insert(:sandbox, parent: root_project)

      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)

      insert(:project_user, user: user, project: root_project, role: :viewer)

      sandbox =
        Lightning.Repo.preload(sandbox, [parent: :project_users], force: true)

      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)
    end

    test "provision_sandbox with editor role is allowed", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :editor)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      assert Sandboxes
             |> Permissions.can?(:provision_sandbox, user, root_project)
    end

    test "sandbox management with editor role", %{
      sandbox: sandbox,
      user: user
    } do
      insert(:project_user, user: user, project: sandbox, role: :editor)
      sandbox = Lightning.Repo.preload(sandbox, :project_users, force: true)
      refute Sandboxes |> Permissions.can?(:delete_sandbox, user, sandbox)
      refute Sandboxes |> Permissions.can?(:update_sandbox, user, sandbox)
    end

    test "check_manage_permissions with mixed roles", %{
      root_project: root_project,
      sandbox: sandbox1,
      sandbox_with_owner: sandbox2
    } do
      user = insert(:user)
      insert(:project_user, user: user, project: root_project, role: :editor)

      insert(:project_user, user: user, project: sandbox1, role: :editor)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      sandbox1 = Lightning.Repo.preload(sandbox1, :project_users, force: true)

      sandboxes = [sandbox1, sandbox2]

      permissions =
        Sandboxes.check_manage_permissions(sandboxes, user, root_project)

      # Editor on root, editor on sandbox: no manage rights without admin/owner
      # on the sandbox itself (or root cascade).
      for sandbox <- sandboxes do
        assert permissions[sandbox.id] == false
      end
    end
  end

  defp future_deletion, do: DateTime.utc_now() |> DateTime.add(7, :day)

  describe "a project scheduled for deletion" do
    test "refuses provisioning for an :owner on a scheduled parent", %{
      root_project_owner: owner,
      root_project: root_project
    } do
      # Control: the same actor CAN provision on a live project, so the
      # refusal below is about the project's lifecycle and not the role.
      assert Sandboxes
             |> Permissions.can?(:provision_sandbox, owner, root_project)

      scheduled_root =
        insert(:project,
          project_users: [%{user_id: owner.id, role: :owner}],
          scheduled_deletion: future_deletion()
        )

      refute Sandboxes
             |> Permissions.can?(:provision_sandbox, owner, scheduled_root)
    end

    test "refuses merge for an :admin on a scheduled target", %{
      root_project: root_project,
      user: user
    } do
      insert(:project_user, user: user, project: root_project, role: :admin)

      root_project =
        Lightning.Repo.preload(root_project, :project_users, force: true)

      assert Sandboxes
             |> Permissions.can?(:merge_sandbox, user, root_project)

      scheduled_target =
        insert(:project,
          project_users: [%{user_id: user.id, role: :admin}],
          scheduled_deletion: future_deletion()
        )

      refute Sandboxes
             |> Permissions.can?(:merge_sandbox, user, scheduled_target)
    end

    test "refuses delete/update for :owner and :admin on a scheduled sandbox",
         %{
           sandbox_owner: owner,
           sandbox_with_owner: owner_sandbox,
           sandbox_admin: admin,
           sandbox_with_admin: admin_sandbox
         } do
      for {actor, sandbox, role} <- [
            {owner, owner_sandbox, :owner},
            {admin, admin_sandbox, :admin}
          ] do
        assert Sandboxes |> Permissions.can?(:delete_sandbox, actor, sandbox)
        assert Sandboxes |> Permissions.can?(:update_sandbox, actor, sandbox)

        scheduled_sandbox =
          insert(:sandbox,
            parent: sandbox.parent,
            project_users: [%{user_id: actor.id, role: role}],
            scheduled_deletion: future_deletion()
          )

        refute Sandboxes
               |> Permissions.can?(:delete_sandbox, actor, scheduled_sandbox)

        refute Sandboxes
               |> Permissions.can?(:update_sandbox, actor, scheduled_sandbox)
      end
    end

    test "refuses the root-project cascade when the root is scheduled, but a direct sandbox role is unaffected",
         %{
           root_project_owner: owner
         } do
      scheduled_root =
        insert(:project,
          project_users: [%{user_id: owner.id, role: :owner}],
          scheduled_deletion: future_deletion()
        )

      live_sandbox_under_scheduled_root =
        insert(:sandbox, parent: scheduled_root)

      # `has_root_project_permission?/2` walks up to the scheduled root, so
      # the cascade path is refused even though the sandbox itself is live.
      refute Sandboxes
             |> Permissions.can?(
               :delete_sandbox,
               owner,
               live_sandbox_under_scheduled_root
             )

      # A direct owner/admin role on the sandbox is evaluated independently
      # of the root's schedule: `role_in?/3` only looks at the sandbox.
      sandbox_owner = insert(:user)

      insert(:project_user,
        user: sandbox_owner,
        project: live_sandbox_under_scheduled_root,
        role: :owner
      )

      live_sandbox_under_scheduled_root =
        Lightning.Repo.preload(
          live_sandbox_under_scheduled_root,
          :project_users,
          force: true
        )

      assert Sandboxes
             |> Permissions.can?(
               :delete_sandbox,
               sandbox_owner,
               live_sandbox_under_scheduled_root
             )
    end

    test "refuses the root-project cascade onto a sandbox scheduled for deletion",
         %{
           root_project_owner: owner,
           root_project: root_project
         } do
      # The root is live and the actor owns it, so the cascade is the only
      # thing that could admit them — a direct role on the sandbox is absent.
      live_sandbox = insert(:sandbox, parent: root_project)

      assert Sandboxes |> Permissions.can?(:delete_sandbox, owner, live_sandbox)
      assert Sandboxes |> Permissions.can?(:update_sandbox, owner, live_sandbox)

      scheduled_sandbox =
        insert(:sandbox,
          parent: root_project,
          scheduled_deletion: future_deletion()
        )

      refute Sandboxes
             |> Permissions.can?(:delete_sandbox, owner, scheduled_sandbox)

      refute Sandboxes
             |> Permissions.can?(:update_sandbox, owner, scheduled_sandbox)
    end
  end
end
