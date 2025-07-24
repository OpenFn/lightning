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

    %{
      project: project,
      keychain_credential: keychain_credential,
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
      project_user = get_project_user(project, owner)

      assert Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               owner,
               %{project_user: project_user, project: project}
             )
    end

    test "admins can create keychain credentials", %{
      project: project,
      admin: admin
    } do
      project_user = get_project_user(project, admin)

      assert Credentials
             |> Bodyguard.permit?(
               :create_keychain_credential,
               admin,
               %{project_user: project_user, project: project}
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
end
