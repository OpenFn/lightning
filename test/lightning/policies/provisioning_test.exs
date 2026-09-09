defmodule Lightning.Policies.ProvisioningTest do
  @moduledoc """
  Tests for the provisioning API's authorization policy.

  The clauses that resolve a `Lightning.Projects.Scope` are held to the
  project's MFA requirement; the ones that cannot be (a project that does not
  exist yet, and a machine credential) are not.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Provisioning
  alias Lightning.Projects.Project

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
end
