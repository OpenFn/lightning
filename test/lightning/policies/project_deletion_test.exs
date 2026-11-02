defmodule Lightning.Policies.ProjectDeletionTest do
  @moduledoc """
  Who may schedule a project, root or sandbox, for deletion, and cancel that:
  a root's owner; a sandbox's owners and admins and those of the project at
  the top of its tree, judged on that root's own facts; and the service
  account with `projects:write`.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectDeletion
  alias Lightning.Scope
  alias Lightning.ServiceAccount.AccessToken

  setup do
    [owner, admin, editor, viewer] = insert_list(4, :user)

    root =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    %{root: root, owner: owner, admin: admin, editor: editor, viewer: viewer}
  end

  describe "a root project" do
    test "only its owner may delete it; another member is refused and a stranger has no standing",
         %{root: root} = users do
      for {user, answer} <- [
            {users.owner, true},
            {users.admin, false},
            {users.editor, false},
            {users.viewer, false},
            {insert(:user), {:error, :no_standing}}
          ] do
        assert decide(:delete_project, user, root) == answer
      end
    end

    test "its owner is refused when they haven't met its MFA requirement" do
      owner = insert(:user, mfa_enabled: false)

      root =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: owner, role: :owner}]
        )

      assert decide(:delete_project, owner, root) == false
    end

    test "a scheduled one is scheduled_for_deletion to its owner, who may cancel it, and refused to the rest",
         %{owner: owner, admin: admin} do
      root =
        insert(:project,
          scheduled_deletion: now(),
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin}
          ]
        )

      assert decide(:delete_project, owner, root) ==
               {:error, :scheduled_for_deletion}

      assert decide(:cancel_project_deletion, owner, root) == true
      assert decide(:cancel_project_deletion, admin, root) == false
    end
  end

  describe "a sandbox" do
    test "its owners and admins may delete it, and its editors and viewers may not" do
      [owner, admin, editor, viewer] = insert_list(4, :user)

      sandbox =
        insert(:sandbox,
          parent: insert(:project),
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      for {user, answer} <- [
            {owner, true},
            {admin, true},
            {editor, false},
            {viewer, false},
            {insert(:user), {:error, :no_standing}}
          ] do
        assert decide(:delete_project, user, sandbox) == answer
      end
    end

    test "the root's owners and admins may delete it and cancel its deletion, however deep, and its other members keep the sandbox's own answer",
         %{root: root} = users do
      sandbox = insert(:sandbox, parent: root)
      below = insert(:sandbox, parent: sandbox)
      scheduled = insert(:sandbox, parent: sandbox, scheduled_deletion: now())

      for {user, answer} <- [
            {users.owner, true},
            {users.admin, true},
            {users.editor, {:error, :no_standing}},
            {users.viewer, {:error, :no_standing}}
          ] do
        assert decide(:delete_project, user, below) == answer
        assert decide(:cancel_project_deletion, user, scheduled) == answer
      end
    end

    test "a member of the root without the sandbox's role keeps the sandbox's refusal",
         %{root: root, editor: editor} do
      sandbox =
        insert(:sandbox,
          parent: root,
          project_users: [%{user: editor, role: :viewer}]
        )

      assert decide(:delete_project, editor, sandbox) == false
    end

    test "the root's admin is judged on the root's MFA requirement" do
      admin = insert(:user, mfa_enabled: false)

      root =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: admin, role: :admin}]
        )

      sandbox = insert(:sandbox, parent: root)

      assert decide(:delete_project, admin, sandbox) == {:error, :no_standing}
    end

    test "a scheduled sandbox is scheduled_for_deletion to the root's admin, and a scheduled root gives no cascade",
         %{admin: admin} do
      root = insert(:project, project_users: [%{user: admin, role: :admin}])
      scheduled = insert(:sandbox, parent: root, scheduled_deletion: now())

      assert decide(:delete_project, admin, scheduled) ==
               {:error, :scheduled_for_deletion}

      scheduled_root =
        insert(:project,
          scheduled_deletion: now(),
          project_users: [%{user: admin, role: :admin}]
        )

      sandbox = insert(:sandbox, parent: scheduled_root)

      assert decide(:delete_project, admin, sandbox) == {:error, :no_standing}
    end
  end

  describe "the service account" do
    test "may delete and cancel on any project with projects:write, and hears which grant without it",
         %{root: root} do
      {account, _key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      sandbox = insert(:sandbox, parent: root, scheduled_deletion: now())

      for action <- [:delete_project, :cancel_project_deletion] do
        {:ok, granted} =
          Scope.fetch(
            %{account | grants: MapSet.new(AccessToken.scopes())},
            root
          )

        {:ok, grantless} = Scope.fetch(%{account | grants: MapSet.new()}, root)

        assert ProjectDeletion.authorize(action, granted, root) == true

        assert ProjectDeletion.authorize(action, grantless, root) ==
                 {:error, {:insufficient_scope, "projects:write"}}
      end

      {:ok, granted} =
        Scope.fetch(
          %{account | grants: MapSet.new(AccessToken.scopes())},
          sandbox
        )

      assert ProjectDeletion.authorize(
               :cancel_project_deletion,
               granted,
               sandbox
             ) ==
               true
    end
  end

  test "a person asked without a scope gets a yes or no", %{
    root: root,
    owner: owner,
    admin: admin
  } do
    assert Permissions.can?(ProjectDeletion, :delete_project, owner, root)
    refute Permissions.can?(ProjectDeletion, :delete_project, admin, root)
  end

  defp decide(action, user, project) do
    {:ok, scope} = Scope.fetch(user, project)
    ProjectDeletion.authorize(action, scope, project)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
