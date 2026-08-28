defmodule Lightning.Policies.CredentialsTest do
  @moduledoc """
  Tests for credential-specific authorization policies.

  These tests ensure that keychain credential operations are properly restricted
  to users with appropriate project roles (owner/admin) and that unauthorized
  users cannot perform these operations.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Policies.Credentials

  defp get_project_user(project, user) do
    Enum.find(project.project_users, &(&1.user_id == user.id))
  end

  setup tags do
    viewer = insert(:user)
    admin = insert(:user)
    owner = insert(:user)
    editor = insert(:user)
    intruder = insert(:user)
    support_user = insert(:user, support_user: true)

    project =
      insert(:project,
        allow_support_access: tags[:allow_support_access],
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ]
      )

    keychain_credential =
      insert(:keychain_credential,
        project: project,
        created_by: owner
      )

    # Scheduling deletion removes no membership rows, so owner/admin/support
    # still hold real project_users rows (or support access) on this project.
    scheduled_project =
      insert(:project,
        allow_support_access: tags[:allow_support_access],
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ],
        scheduled_deletion: DateTime.utc_now() |> DateTime.add(7, :day)
      )

    scheduled_keychain_credential =
      insert(:keychain_credential,
        project: scheduled_project,
        created_by: owner
      )

    %{
      project: project,
      keychain_credential: keychain_credential,
      scheduled_project: scheduled_project,
      scheduled_keychain_credential: scheduled_keychain_credential,
      viewer: viewer,
      admin: admin,
      owner: owner,
      editor: editor,
      intruder: intruder,
      support_user: support_user
    }
  end

  describe "KeychainCredential creation" do
    test "owners can create keychain credentials", %{
      project: project,
      owner: owner
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               owner,
               project
             )
    end

    test "admins can create keychain credentials", %{
      project: project,
      admin: admin
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               admin,
               project
             )
    end

    test "editors cannot create keychain credentials", %{
      project: project,
      editor: editor
    } do
      project_user = get_project_user(project, editor)

      refute Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               editor,
               %{project_user: project_user, project: project}
             )
    end

    test "viewers cannot create keychain credentials", %{
      project: project,
      viewer: viewer
    } do
      project_user = get_project_user(project, viewer)

      refute Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               viewer,
               %{project_user: project_user, project: project}
             )
    end

    test "non-project members cannot create keychain credentials", %{
      project: project,
      intruder: intruder
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               intruder,
               project
             )
    end

    @tag allow_support_access: true
    test "support users can create keychain credentials", %{
      project: project,
      support_user: support_user
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               support_user,
               project
             )
    end
  end

  describe "KeychainCredential editing" do
    test "owners can edit keychain credentials", %{
      keychain_credential: keychain_credential,
      owner: owner
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :edit_keychain_credential,
               owner,
               keychain_credential
             )
    end

    test "admins can edit keychain credentials", %{
      keychain_credential: keychain_credential,
      admin: admin
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :edit_keychain_credential,
               admin,
               keychain_credential
             )
    end

    test "editors cannot edit keychain credentials", %{
      keychain_credential: keychain_credential,
      editor: editor
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :edit_keychain_credential,
               editor,
               keychain_credential
             )
    end

    test "viewers cannot edit keychain credentials", %{
      keychain_credential: keychain_credential,
      viewer: viewer
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :edit_keychain_credential,
               viewer,
               keychain_credential
             )
    end

    test "non-project members cannot edit keychain credentials", %{
      keychain_credential: keychain_credential,
      intruder: intruder
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :edit_keychain_credential,
               intruder,
               keychain_credential
             )
    end

    test "refuses a support user on a project that has not allowed support access",
         %{
           keychain_credential: keychain_credential,
           support_user: support_user
         } do
      for action <- [
            :edit_keychain_credential,
            :delete_keychain_credential,
            :view_keychain_credential
          ] do
        refute Credentials
               |> Bodyguard.permit?(action, support_user, keychain_credential),
               "#{action} was granted without allow_support_access"
      end
    end

    @tag allow_support_access: true
    test "support users can edit keychain credentials", %{
      keychain_credential: keychain_credential,
      support_user: support_user
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :edit_keychain_credential,
               support_user,
               keychain_credential
             )
    end

    # An explicit membership row decides, exactly as it does in
    # Lightning.Policies.ProjectUsers. Support access stands in for someone with
    # no row; it must not upgrade a row that was deliberately set low, or
    # "this person is read-only here" could not be expressed at all.
    @tag allow_support_access: true
    test "refuses a support user pinned to a viewer role, even with support access",
         %{
           project: project,
           keychain_credential: keychain_credential,
           support_user: support_user
         } do
      insert(:project_user, project: project, user: support_user, role: :viewer)

      for action <- [
            :edit_keychain_credential,
            :delete_keychain_credential,
            :view_keychain_credential
          ] do
        refute Credentials
               |> Bodyguard.permit?(action, support_user, keychain_credential),
               "#{action} was granted to a support user holding a :viewer row"
      end
    end
  end

  describe "KeychainCredential deletion" do
    test "owners can delete keychain credentials", %{
      keychain_credential: keychain_credential,
      owner: owner
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :delete_keychain_credential,
               owner,
               keychain_credential
             )
    end

    test "admins can delete keychain credentials", %{
      keychain_credential: keychain_credential,
      admin: admin
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :delete_keychain_credential,
               admin,
               keychain_credential
             )
    end

    test "editors cannot delete keychain credentials", %{
      keychain_credential: keychain_credential,
      editor: editor
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :delete_keychain_credential,
               editor,
               keychain_credential
             )
    end

    test "viewers cannot delete keychain credentials", %{
      keychain_credential: keychain_credential,
      viewer: viewer
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :delete_keychain_credential,
               viewer,
               keychain_credential
             )
    end

    test "non-project members cannot delete keychain credentials", %{
      keychain_credential: keychain_credential,
      intruder: intruder
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :delete_keychain_credential,
               intruder,
               keychain_credential
             )
    end

    @tag allow_support_access: true
    test "support users can delete keychain credentials", %{
      keychain_credential: keychain_credential,
      support_user: support_user
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :delete_keychain_credential,
               support_user,
               keychain_credential
             )
    end
  end

  describe "KeychainCredential viewing" do
    test "owners can view keychain credentials", %{
      keychain_credential: keychain_credential,
      owner: owner
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :view_keychain_credential,
               owner,
               keychain_credential
             )
    end

    test "admins can view keychain credentials", %{
      keychain_credential: keychain_credential,
      admin: admin
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :view_keychain_credential,
               admin,
               keychain_credential
             )
    end

    test "editors cannot view keychain credentials", %{
      keychain_credential: keychain_credential,
      editor: editor
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :view_keychain_credential,
               editor,
               keychain_credential
             )
    end

    test "viewers cannot view keychain credentials", %{
      keychain_credential: keychain_credential,
      viewer: viewer
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :view_keychain_credential,
               viewer,
               keychain_credential
             )
    end

    test "non-project members cannot view keychain credentials", %{
      keychain_credential: keychain_credential,
      intruder: intruder
    } do
      refute Credentials
             |> Bodyguard.permit?(
               :view_keychain_credential,
               intruder,
               keychain_credential
             )
    end

    @tag allow_support_access: true
    test "support users can view keychain credentials", %{
      keychain_credential: keychain_credential,
      support_user: support_user
    } do
      assert Credentials
             |> Bodyguard.permit?(
               :view_keychain_credential,
               support_user,
               keychain_credential
             )
    end
  end

  defp scheduled_deletion_cases(project, scheduled_project, kc, scheduled_kc) do
    [
      {:create_keychain_credential, project, scheduled_project},
      {:edit_keychain_credential, kc, scheduled_kc},
      {:delete_keychain_credential, kc, scheduled_kc},
      {:view_keychain_credential, kc, scheduled_kc}
    ]
  end

  describe "a project scheduled for deletion" do
    test "refuses every keychain-credential action for :owner and :admin", %{
      project: project,
      scheduled_project: scheduled_project,
      keychain_credential: keychain_credential,
      scheduled_keychain_credential: scheduled_keychain_credential,
      owner: owner,
      admin: admin
    } do
      cases =
        scheduled_deletion_cases(
          project,
          scheduled_project,
          keychain_credential,
          scheduled_keychain_credential
        )

      for actor <- [owner, admin], {action, live, scheduled} <- cases do
        # Control: the same actor CAN act on a live project, so every
        # refusal below is about the project's lifecycle, not the role.
        assert Credentials |> Bodyguard.permit?(action, actor, live),
               "#{action} was refused on a live project"

        refute Credentials |> Bodyguard.permit?(action, actor, scheduled),
               "#{action} was granted on a project scheduled for deletion"
      end
    end

    @tag allow_support_access: true
    test "refuses every keychain-credential action for a support user", %{
      project: project,
      scheduled_project: scheduled_project,
      keychain_credential: keychain_credential,
      scheduled_keychain_credential: scheduled_keychain_credential,
      support_user: support_user
    } do
      cases =
        scheduled_deletion_cases(
          project,
          scheduled_project,
          keychain_credential,
          scheduled_keychain_credential
        )

      for {action, live, scheduled} <- cases do
        assert Credentials |> Bodyguard.permit?(action, support_user, live),
               "#{action} was refused on a live project"

        refute Credentials
               |> Bodyguard.permit?(action, support_user, scheduled),
               "#{action} was granted on a project scheduled for deletion"
      end
    end
  end
end
