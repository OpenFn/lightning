defmodule Lightning.Policies.ProvisioningTest do
  @moduledoc """
  Tests for the provisioning API's authorization policy.

  The clauses that resolve a `Lightning.Scope` are held to the
  project's MFA requirement; the ones that cannot be (a project that does not
  exist yet, and a machine credential) are not.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Provisioning
  alias Lightning.Projects.Project
  alias Lightning.ServiceAccount.AccessToken

  describe ":provision_project on a project that requires MFA" do
    test "is refused for an unenrolled :owner or :admin" do
      for role <- [:owner, :admin] do
        actor = insert(:user, mfa_enabled: false)

        unrestricted_project =
          insert(:project, project_users: [%{user_id: actor.id, role: role}])

        # Control: the same unenrolled actor CAN provision a project that
        # does not require MFA, so the refusal below is about the
        # requirement and not about the role.
        assert Permissions.can?(
                 Provisioning,
                 :provision_project,
                 actor,
                 unrestricted_project
               )

        mfa_project =
          insert(:project,
            requires_mfa: true,
            project_users: [%{user_id: actor.id, role: role}]
          )

        refute Permissions.can?(
                 Provisioning,
                 :provision_project,
                 actor,
                 mfa_project
               )

        assert Provisioning.authorize(:provision_project, actor, mfa_project) ==
                 {:error, :forbidden}
      end
    end

    test "is allowed once the :owner or :admin has enrolled" do
      for role <- [:owner, :admin] do
        actor = insert(:user, mfa_enabled: true)

        mfa_project =
          insert(:project,
            requires_mfa: true,
            project_users: [%{user_id: actor.id, role: role}]
          )

        assert Permissions.can?(
                 Provisioning,
                 :provision_project,
                 actor,
                 mfa_project
               )
      end
    end

    test "is refused for an :editor or :viewer whether or not they have enrolled" do
      for role <- [:editor, :viewer], mfa_enabled <- [false, true] do
        actor = insert(:user, mfa_enabled: mfa_enabled)

        mfa_project =
          insert(:project,
            requires_mfa: true,
            project_users: [%{user_id: actor.id, role: role}]
          )

        refute Permissions.can?(
                 Provisioning,
                 :provision_project,
                 actor,
                 mfa_project
               )
      end
    end
  end

  describe "clauses that resolve no project membership" do
    test "a superuser can still create a project that does not exist yet" do
      # `%Project{id: nil}` has no `requires_mfa` to read and no members to
      # consult; the MFA guard cannot apply and must not have been added here.
      superuser = insert(:user, role: :superuser, mfa_enabled: false)

      assert Permissions.can?(
               Provisioning,
               :provision_project,
               superuser,
               %Project{id: nil}
             )
    end

    test "a repo connection is unaffected by the project's MFA requirement" do
      # No MFA concept applies to a machine credential, so the connection
      # keeps working on a project its human members must enrol to touch.
      project = insert(:project, requires_mfa: true)
      repo_connection = insert(:project_repo_connection, project: project)

      for action <- [:provision_project, :describe_project] do
        assert Permissions.can?(Provisioning, action, repo_connection, project)
      end
    end
  end

  describe ":describe_project" do
    test "inherits the MFA requirement from :access_project" do
      actor = insert(:user, mfa_enabled: false)

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user_id: actor.id, role: :viewer}]
        )

      unrestricted_project =
        insert(:project, project_users: [%{user_id: actor.id, role: :viewer}])

      assert Permissions.can?(
               Provisioning,
               :describe_project,
               actor,
               unrestricted_project
             )

      refute Permissions.can?(
               Provisioning,
               :describe_project,
               actor,
               mfa_project
             )
    end
  end

  describe "a scope for one project" do
    test "is refused another project's subject" do
      owner = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: owner.id, role: :owner}])

      repo_connection = insert(:project_repo_connection, project: project)
      other = insert(:project)

      {:ok, owner_scope} = Lightning.Scope.fetch(owner, project)
      {:ok, connection_scope} = Lightning.Scope.fetch(repo_connection, project)

      for action <- [:provision_project, :describe_project],
          scope <- [
            owner_scope,
            connection_scope,
            Lightning.Scope.new(repo_connection)
          ] do
        assert Provisioning.authorize(action, scope, other) ==
                 {:error, :forbidden}
      end

      # Shows the refusals above are about the project, not the scopes.
      for action <- [:provision_project, :describe_project],
          scope <- [owner_scope, connection_scope] do
        assert Provisioning.authorize(action, scope, project) == true
      end
    end
  end

  describe "an operator on an existing project" do
    setup do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      %{account: account, project: insert(:project)}
    end

    test "is refused both actions without projects:provision, whatever else it holds",
         %{account: account, project: project} do
      account = %{account | grants: MapSet.new(AccessToken.scopes())}

      for action <- [:provision_project, :describe_project] do
        assert Provisioning.authorize(action, account, project) ==
                 {:error, {:insufficient_scope, "projects:provision"}}
      end
    end

    test "may provision with projects:provision", %{
      account: account,
      project: project
    } do
      account = %{account | grants: MapSet.new(["projects:provision"])}

      assert Provisioning.authorize(:provision_project, account, project) == true
    end

    test "needs projects:write as well to describe, as :access_project does", %{
      account: account,
      project: project
    } do
      provision_only = %{account | grants: MapSet.new(["projects:provision"])}

      both = %{
        account
        | grants: MapSet.new(["projects:provision", "projects:write"])
      }

      assert Provisioning.authorize(:describe_project, provision_only, project) ==
               {:error, :forbidden}

      assert Provisioning.authorize(:describe_project, both, project) == true
    end

    test "hears the project is scheduled for deletion only once allowed", %{
      account: account
    } do
      project =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.add(1, :day)
        )

      assert Provisioning.authorize(:provision_project, account, project) ==
               {:error, {:insufficient_scope, "projects:provision"}}

      account = %{account | grants: MapSet.new(["projects:provision"])}

      assert Provisioning.authorize(:provision_project, account, project) ==
               {:error, :scheduled_for_deletion}
    end
  end

  describe ":create_project" do
    test "is allowed for a superuser" do
      superuser = insert(:user, role: :superuser)

      assert Provisioning.authorize(:create_project, superuser, nil)
    end

    test "is allowed for an operator holding projects:write, and only then" do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      assert Provisioning.authorize(
               :create_project,
               %{account | grants: MapSet.new(["projects:write"])},
               nil
             ) == true

      assert Provisioning.authorize(
               :create_project,
               %{account | grants: MapSet.new(["users:write"])},
               nil
             ) == {:error, {:insufficient_scope, "projects:write"}}
    end

    test "is refused for a user who is not a superuser, whatever roles they hold elsewhere" do
      for role <- [:owner, :admin, :editor, :viewer] do
        user = insert(:user)
        insert(:project, project_users: [%{user_id: user.id, role: role}])

        assert Provisioning.authorize(:create_project, user, nil) ==
                 {:error, :forbidden}

        assert Provisioning.authorize(:provision_project, user, %Project{
                 id: nil
               }) == {:error, :forbidden}
      end
    end

    # A repo connection holds no `projects:write`, so the grant refuses it first.
    test "is refused for a repo connection" do
      repo_connection = insert(:project_repo_connection)

      assert Provisioning.authorize(:create_project, repo_connection, nil) ==
               {:error, {:insufficient_scope, "projects:write"}}
    end
  end
end
