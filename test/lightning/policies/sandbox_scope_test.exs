defmodule Lightning.Policies.SandboxScopeTest do
  @moduledoc """
  How `Lightning.Policies.Sandboxes` and `Lightning.Policies.RepoConnections`
  decide for a `%Scope{}`, the way the API asks.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Policies.RepoConnections
  alias Lightning.Policies.Sandboxes
  alias Lightning.Scope

  defp decide(policy, action, actor, project) do
    {:ok, scope} = Scope.fetch(Scope.new(actor), project)
    policy.authorize(action, scope, project)
  end

  defp service_account(grants) do
    {account, _key} = Lightning.ServiceAccountHelpers.service_account_with_key()
    %{account | grants: MapSet.new(grants)}
  end

  describe "provisioning and merging into a project" do
    test "an editor or above may, anyone else is refused, and the service account never may" do
      [owner, admin, editor, viewer, stranger, unenrolled] =
        insert_list(6, :user)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: unenrolled, role: :owner}]
        )

      scheduled =
        insert(:project,
          scheduled_deletion: DateTime.utc_now(),
          project_users: [%{user: owner, role: :owner}]
        )

      for action <- [:provision_sandbox, :merge_sandbox] do
        answers =
          for {actor, subject} <- [
                {owner, project},
                {admin, project},
                {editor, project},
                {viewer, project},
                {stranger, project},
                {unenrolled, mfa_project},
                {owner, scheduled},
                {service_account(["projects:write"]), project}
              ],
              do: decide(Sandboxes, action, actor, subject)

        assert answers == [
                 true,
                 true,
                 true,
                 false,
                 {:error, :no_standing},
                 false,
                 {:error, :scheduled_for_deletion},
                 false
               ]
      end
    end
  end

  describe "managing a sandbox" do
    test "its owner or admin may, and so may the root's owner or admin, but never on the root itself" do
      [root_owner, sandbox_admin, sandbox_editor, root_admin_only] =
        insert_list(4, :user)

      root =
        insert(:project,
          project_users: [
            %{user: root_owner, role: :owner},
            %{user: root_admin_only, role: :admin}
          ]
        )

      sandbox =
        insert(:project,
          parent: root,
          project_users: [
            %{user: sandbox_admin, role: :admin},
            %{user: sandbox_editor, role: :editor}
          ]
        )

      nested = insert(:project, parent: sandbox)

      for action <- [:update_sandbox, :delete_sandbox] do
        answers =
          for {actor, subject} <- [
                {sandbox_admin, sandbox},
                {sandbox_editor, sandbox},
                {root_admin_only, sandbox},
                {root_owner, nested},
                {sandbox_admin, nested},
                {root_owner, root},
                {service_account(["projects:write"]), sandbox}
              ],
              do: decide(Sandboxes, action, actor, subject)

        assert answers == [
                 true,
                 false,
                 true,
                 true,
                 {:error, :no_standing},
                 false,
                 false
               ]
      end
    end

    test "the root's admin is still held to the sandbox's MFA requirement and its scheduled deletion" do
      root_admin = insert(:user)
      root = insert(:project, project_users: [%{user: root_admin, role: :admin}])
      mfa_sandbox = insert(:project, parent: root, requires_mfa: true)

      scheduled_sandbox =
        insert(:project, parent: root, scheduled_deletion: DateTime.utc_now())

      assert decide(Sandboxes, :update_sandbox, root_admin, mfa_sandbox) == false

      assert decide(Sandboxes, :update_sandbox, root_admin, scheduled_sandbox) ==
               {:error, :scheduled_for_deletion}
    end

    test "the service account is refused whatever grants it holds, and a person passes the check before a target" do
      sandbox = insert(:project, parent: insert(:project))

      for grants <- [[], ["projects:write"]] do
        {:ok, scope} = Scope.fetch(Scope.new(service_account(grants)), sandbox)
        assert Sandboxes.authorize(:update_sandbox, scope, sandbox) == false
      end

      assert Sandboxes.authorize(
               :update_sandbox,
               Scope.new(insert(:user)),
               :before_target
             )
    end
  end

  describe "a project's repo connection" do
    test "any member reads it, an admin or above writes it, an editor or above syncs it, and only people" do
      [owner, admin, editor, viewer, stranger] = insert_list(5, :user)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      account = service_account(["projects:write"])

      table =
        for action <- [
              :see_repo_connection,
              :write_repo_connection,
              :sync_repo_connection
            ] do
          for actor <- [owner, admin, editor, viewer, stranger, account] do
            decide(RepoConnections, action, actor, project)
          end
        end

      no_standing = {:error, :no_standing}

      assert table == [
               [true, true, true, true, no_standing, false],
               [true, true, false, false, no_standing, false],
               [true, true, true, false, no_standing, false]
             ]

      assert RepoConnections.authorize(:see_repo_connection, owner, project) ==
               false
    end
  end
end
