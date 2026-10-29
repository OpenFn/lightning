defmodule Lightning.Policies.ProvisioningTest do
  @moduledoc """
  Tests for the provisioning API's authorization policy.

  A person is held to the project's MFA requirement; a superuser creating a
  project and a repo connection are not.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Policies.Permissions
  alias Lightning.Scope
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
        assert permit_target(actor, :provision_project, unrestricted_project) ==
                 :ok

        mfa_project =
          insert(:project,
            requires_mfa: true,
            project_users: [%{user_id: actor.id, role: role}]
          )

        assert permit_target(actor, :provision_project, mfa_project) ==
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

        assert permit_target(actor, :provision_project, mfa_project) == :ok
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

        assert permit_target(actor, :provision_project, mfa_project) ==
                 {:error, :forbidden}
      end
    end

    test "does not apply to a repo connection" do
      # No MFA concept applies to a machine credential, so the connection
      # keeps working on a project its human members must enrol to touch.
      project = insert(:project, requires_mfa: true)
      repo_connection = insert(:project_repo_connection, project: project)

      for action <- [:provision_project, :describe_project] do
        assert permit_target(repo_connection, action, project) == :ok
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

      assert permit_target(actor, :describe_project, unrestricted_project) ==
               :ok

      assert permit_target(actor, :describe_project, mfa_project) ==
               {:error, :forbidden}
    end
  end

  describe "a scope for one project" do
    test "is refused another project's subject" do
      owner = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: owner.id, role: :owner}])

      repo_connection = insert(:project_repo_connection, project: project)
      other = insert(:project)

      {:ok, owner_scope} = Scope.fetch(owner, project)
      {:ok, connection_scope} = Scope.fetch(repo_connection, project)

      for action <- [:provision_project, :describe_project],
          scope <- [owner_scope, connection_scope, Scope.new(repo_connection)] do
        assert Permissions.permit(:provisioning, action, scope, other) ==
                 {:error, :forbidden}
      end

      # Shows the refusals above are about the project, not the scopes.
      for action <- [:provision_project, :describe_project],
          scope <- [owner_scope, connection_scope] do
        assert Permissions.permit(:provisioning, action, scope, project) == :ok
      end
    end
  end

  describe "an operator on an existing project" do
    setup do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      %{account: account, project: insert(:project)}
    end

    test "describes it, but is refused provisioning it, with every grant the token endpoint issues",
         %{account: account, project: project} do
      account = %{account | grants: MapSet.new(AccessToken.scopes())}

      assert permit_target(account, :describe_project, project) == :ok

      assert permit_target(account, :provision_project, project) ==
               {:error, :forbidden}
    end

    test "describes it holding only projects:write", %{
      account: account,
      project: project
    } do
      account = %{account | grants: MapSet.new(["projects:write"])}

      assert permit_target(account, :describe_project, project) == :ok
    end

    test "is refused both holding neither projects grant, hearing projects:write",
         %{account: account, project: project} do
      account = %{account | grants: MapSet.new(["users:write"])}

      for action <- [:provision_project, :describe_project] do
        assert permit_target(account, action, project) ==
                 {:error, {:insufficient_scope, "projects:write"}}
      end
    end

    test "is refused provisioning even with every grant, projects:provision included",
         %{account: account, project: project} do
      account = %{
        account
        | grants: MapSet.new(AccessToken.scopes() ++ ["projects:provision"])
      }

      assert permit_target(account, :provision_project, project) ==
               {:error, :forbidden}
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

      assert permit_target(provision_only, :describe_project, project) ==
               {:error, :forbidden}

      assert permit_target(both, :describe_project, project) == :ok
    end

    test "is refused provisioning a project scheduled for deletion without hearing of the schedule",
         %{account: account} do
      project =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.add(1, :day)
        )

      assert permit_target(account, :provision_project, project) ==
               {:error, {:insufficient_scope, "projects:write"}}

      account = %{account | grants: MapSet.new(["projects:provision"])}

      assert permit_target(account, :provision_project, project) ==
               {:error, :forbidden}
    end
  end

  describe ":create_project" do
    test "is allowed for a superuser, who is not held to MFA" do
      superuser = insert(:user, role: :superuser, mfa_enabled: false)

      assert permit_create(superuser) == :ok
    end

    test "is allowed for an operator holding projects:write, and only then" do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      assert permit_create(%{account | grants: MapSet.new(["projects:write"])}) ==
               :ok

      assert permit_create(%{account | grants: MapSet.new(["users:write"])}) ==
               {:error, {:insufficient_scope, "projects:write"}}
    end

    test "is refused for a user who is not a superuser, whatever roles they hold elsewhere" do
      for role <- [:owner, :admin, :editor, :viewer] do
        user = insert(:user)
        insert(:project, project_users: [%{user_id: user.id, role: role}])

        assert permit_create(user) == {:error, :forbidden}
      end
    end

    # A repo connection holds no `projects:write`, so the grant refuses it first.
    test "is refused for a repo connection" do
      repo_connection = insert(:project_repo_connection)

      assert permit_create(repo_connection) ==
               {:error, {:insufficient_scope, "projects:write"}}
    end
  end

  describe ":provision_new_project" do
    test "is allowed for a superuser" do
      superuser = insert(:user, role: :superuser, mfa_enabled: false)

      assert permit_new(superuser) == :ok
    end

    test "is refused for a person who is not a superuser" do
      user = insert(:user)
      insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      assert permit_new(user) == {:error, :forbidden}
    end

    test "is refused for the service account, and names projects:write to one without it" do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      assert permit_new(%{account | grants: MapSet.new(["projects:write"])}) ==
               {:error, :forbidden}

      assert permit_new(%{account | grants: MapSet.new(["users:write"])}) ==
               {:error, {:insufficient_scope, "projects:write"}}
    end

    test "is refused for a repo connection, which holds no projects:write" do
      assert permit_new(insert(:project_repo_connection)) ==
               {:error, {:insufficient_scope, "projects:write"}}
    end
  end

  describe "before the target is loaded" do
    setup do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      %{account: account}
    end

    test "describing needs either projects grant, and names projects:write without one",
         %{account: account} do
      assert permit(account, [], :describe_project) ==
               {:error, {:insufficient_scope, "projects:write"}}

      assert permit(account, ["projects:write"], :describe_project) == :ok
      assert permit(account, ["projects:provision"], :describe_project) == :ok
    end

    test "provisioning needs either grant, and names projects:write without one",
         %{account: account} do
      assert permit(account, ["users:write"], :provision_project) ==
               {:error, {:insufficient_scope, "projects:write"}}

      assert permit(account, ["projects:write"], :provision_project) == :ok
      assert permit(account, ["projects:provision"], :provision_project) == :ok
    end

    test "passes a repo connection" do
      scope = Scope.new(insert(:project_repo_connection))

      for action <- [:describe_project, :provision_project] do
        assert Permissions.permit(:provisioning, action, scope) == :ok
      end
    end

    defp permit(account, grants, action) do
      scope = Scope.new(%{account | grants: MapSet.new(grants)})
      Permissions.permit(:provisioning, action, scope)
    end
  end

  describe "a caller with no standing on the project" do
    test "is told so, for the API to answer as a project that doesn't exist" do
      user = insert(:user)
      project = insert(:project)

      for action <- [:provision_project, :describe_project] do
        assert permit_target(user, action, project) == {:error, :no_standing}
      end
    end
  end

  defp permit_target(actor, action, project) do
    {:ok, scope} = Scope.fetch(actor, project)
    Permissions.permit(:provisioning, action, scope, project)
  end

  defp permit_create(actor),
    do: Permissions.permit(:provisioning, :create_project, Scope.new(actor), nil)

  defp permit_new(actor),
    do:
      Permissions.permit(
        :provisioning,
        :provision_new_project,
        Scope.new(actor),
        nil
      )
end
