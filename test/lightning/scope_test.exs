defmodule Lightning.ScopeTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Project
  alias Lightning.Scope

  setup do
    editor = insert(:user)

    live_project =
      insert(:project, project_users: [%{user_id: editor.id, role: :editor}])

    scheduled_deleted_project =
      insert(:project,
        project_users: [%{user_id: editor.id, role: :editor}],
        scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    %{
      editor: editor,
      live_project: live_project,
      scheduled_deleted_project: scheduled_deleted_project
    }
  end

  test "an editor on a live project gets their role", %{
    editor: editor,
    live_project: project
  } do
    assert {:ok, scope} = Scope.fetch(editor, project)
    assert scope.role == :editor
    assert scope.actor == editor
  end

  test "a scope from new/1 gains the project's facts, as the actor would", %{
    editor: editor,
    live_project: project
  } do
    assert Scope.fetch(Scope.new(editor), project) ==
             Scope.fetch(editor, project)
  end

  test "a scheduled-deleted project resolves, and says so", %{
    editor: editor,
    live_project: live_project,
    scheduled_deleted_project: project
  } do
    assert {:ok, %Scope{scheduled_for_deletion?: true, role: :editor}} =
             Scope.fetch(editor, project)

    assert {:ok, %Scope{scheduled_for_deletion?: false}} =
             Scope.fetch(editor, live_project)
  end

  test "a hand-built project struct cannot hide that it is scheduled", %{
    editor: editor,
    scheduled_deleted_project: project
  } do
    # scheduled_deletion is nil on this struct because nothing read it. Without
    # the reload the scope would say the project is live.
    fake = %Project{id: project.id}

    assert {:ok, %Scope{scheduled_for_deletion?: true}} =
             Scope.fetch(editor, fake)
  end

  describe "subject shapes" do
    test "a bare project id resolves", %{editor: editor, live_project: project} do
      assert {:ok, scope} = Scope.fetch(editor, project.id)
      assert scope.role == :editor
    end

    test "anything carrying a project_id resolves", %{
      editor: editor,
      live_project: project
    } do
      dataclip = insert(:dataclip, project: project)

      assert {:ok, scope} = Scope.fetch(editor, dataclip)
      assert scope.role == :editor
    end

    test "an unsaved project is no such project", %{editor: editor} do
      assert {:error, :no_such_project} = Scope.fetch(editor, %Project{})
    end

    test "a malformed id is refused, not raised", %{editor: editor} do
      assert {:error, :no_such_project} = Scope.fetch(editor, "not-a-uuid")
      assert {:error, :no_such_project} = Scope.fetch(editor, nil)
    end

    test "an id for a project that does not exist is no such project", %{
      editor: editor
    } do
      assert {:error, :no_such_project} =
               Scope.fetch(editor, Ecto.UUID.generate())
    end
  end

  describe "fetch_all/2" do
    test "gives each project the scope fetch/2 would, leaving out ids it can't resolve",
         %{editor: editor, live_project: project} do
      elsewhere = insert(:project)

      scopes =
        Scope.fetch_all(editor, [
          project.id,
          elsewhere.id,
          Ecto.UUID.generate(),
          "not-a-uuid"
        ])

      assert Map.keys(scopes) |> Enum.sort() ==
               Enum.sort([project.id, elsewhere.id])

      for id <- [project.id, elsewhere.id],
          do: assert({:ok, scopes[id]} == Scope.fetch(editor, id))
    end

    test "leaves out every project but a repo connection's own" do
      [own, other] = insert_pair(:project)
      repo_connection = insert(:project_repo_connection, project: own)

      assert Map.keys(Scope.fetch_all(repo_connection, [own.id, other.id])) ==
               [own.id]
    end
  end

  describe "non-members" do
    test "get no role but still resolve", %{live_project: project} do
      stranger = insert(:user)

      assert {:ok, scope} = Scope.fetch(stranger, project)
      assert scope.role == nil
      assert scope.project_user == nil
    end
  end

  describe "support users" do
    test "a support user on a consenting project has support access" do
      support_user = insert(:user, support_user: true)
      project = insert(:project, allow_support_access: true)

      assert {:ok, scope} = Scope.fetch(support_user, project)
      assert scope.support_user? == true
      assert scope.support? == true
    end

    test "a support user on a non-consenting project does not" do
      support_user = insert(:user, support_user: true)
      project = insert(:project, allow_support_access: false)

      assert {:ok, scope} = Scope.fetch(support_user, project)
      assert scope.support_user? == true
      assert scope.support? == false
    end

    test "a support user sees a scheduled-deleted project as scheduled" do
      support_user = insert(:user, support_user: true)

      project =
        insert(:project,
          allow_support_access: true,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:ok, %Scope{scheduled_for_deletion?: true, support?: true}} =
               Scope.fetch(support_user, project)
    end
  end

  describe "the MFA requirement" do
    test "is satisfied on a project that does not require it, either way" do
      project = insert(:project, requires_mfa: false)

      for mfa_enabled <- [false, true] do
        user = insert(:user, mfa_enabled: mfa_enabled)

        assert {:ok, scope} = Scope.fetch(user, project)
        assert scope.mfa_satisfied? == true
      end
    end

    test "is satisfied on a requiring project by an enrolled user" do
      project = insert(:project, requires_mfa: true)
      user = insert(:user, mfa_enabled: true)

      assert {:ok, scope} = Scope.fetch(user, project)
      assert scope.mfa_satisfied? == true
    end

    test "is not satisfied on a requiring project by an unenrolled user" do
      project = insert(:project, requires_mfa: true)
      user = insert(:user, mfa_enabled: false)

      assert {:ok, scope} = Scope.fetch(user, project)
      assert scope.mfa_satisfied? == false
    end

    # An unset flag is not "not yet decided", it is not enrolled.
    test "is not satisfied on a requiring project by an unset enrolment flag" do
      project = insert(:project, requires_mfa: true)
      user = insert(:user, mfa_enabled: nil)

      assert {:ok, scope} = Scope.fetch(user, project)
      assert scope.mfa_satisfied? == false
    end

    test "binds a support user as much as a member" do
      support_user = insert(:user, support_user: true, mfa_enabled: false)

      project =
        insert(:project, requires_mfa: true, allow_support_access: true)

      assert {:ok, scope} = Scope.fetch(support_user, project)
      assert scope.support? == true
      assert scope.mfa_satisfied? == false
    end

    # Pins the fail-closed default: a scope built without going through
    # `new/1` should refuse, not silently pass.
    test "defaults to false on a scope that never went through new/1" do
      assert %Scope{actor: insert(:user)}.mfa_satisfied? == false
    end
  end

  describe "new/1" do
    test "a person holds every grant and has met no project's MFA rule yet" do
      user = insert(:user, support_user: true, mfa_enabled: false)

      assert %Scope{
               actor: ^user,
               grants: :all,
               instance_role: nil,
               support_user?: true,
               mfa_satisfied?: true,
               project: nil,
               role: nil
             } = Scope.new(user)
    end

    test "a superuser's instance role is :superuser" do
      assert Scope.new(insert(:user, role: :superuser)).instance_role ==
               :superuser
    end

    test "a service account holds its token's grants and is an operator" do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      account = %{account | grants: MapSet.new(["projects:write"])}

      assert %Scope{
               actor: ^account,
               instance_role: :operator,
               mfa_satisfied?: true
             } = scope = Scope.new(account)

      assert scope.grants == MapSet.new(["projects:write"])
    end

    test "a repo connection holds only projects:provision and no instance role" do
      repo_connection = insert(:project_repo_connection)

      assert %Scope{
               actor: ^repo_connection,
               instance_role: nil,
               mfa_satisfied?: true
             } = scope = Scope.new(repo_connection)

      assert scope.grants == MapSet.new(["projects:provision"])
    end

    test "a hand-built scope holds no grant" do
      assert %Scope{actor: insert(:user)}.grants == MapSet.new()
    end

    test "only a person can own a credential" do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      assert Scope.new(insert(:user)).can_own_credentials?
      refute Scope.new(account).can_own_credentials?
      refute Scope.new(insert(:project_repo_connection)).can_own_credentials?
      refute %Scope{actor: insert(:user)}.can_own_credentials?
    end
  end

  describe "allows?/2" do
    test "a person is allowed any grant" do
      assert Scope.allows?(Scope.new(insert(:user)), "projects:write")
    end

    test "a token is allowed only the grants it carries" do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      scope = Scope.new(%{account | grants: MapSet.new(["users:read"])})

      assert Scope.allows?(scope, "users:read")
      refute Scope.allows?(scope, "users:write")
    end

    test "a repo connection is allowed nothing" do
      refute Scope.allows?(
               Scope.new(insert(:project_repo_connection)),
               "projects:write"
             )
    end
  end

  describe "holds_role?/2 and operator?/1" do
    test "a member holds their own role and no other", %{
      editor: editor,
      live_project: project
    } do
      {:ok, scope} = Scope.fetch(editor, project)

      assert Scope.holds_role?(scope, [:editor, :admin])
      refute Scope.holds_role?(scope, [:owner, :admin])
      refute Scope.operator?(scope)
    end

    test "an operator holds every role", %{live_project: project} do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      {:ok, scope} = Scope.fetch(account, project)

      assert Scope.operator?(scope)
      assert Scope.holds_role?(scope, [:owner])
    end

    test "a superuser gets no project role from their instance role" do
      superuser = insert(:user, role: :superuser)
      {:ok, scope} = Scope.fetch(superuser, insert(:project))

      refute Scope.operator?(scope)
      refute Scope.holds_role?(scope, [:owner, :admin, :editor, :viewer])
    end
  end

  describe "role_in?/3" do
    test "is true for a role-holding user on a project without the requirement",
         %{editor: editor, live_project: project} do
      assert Scope.role_in?(editor, project, [:editor])
      refute Scope.role_in?(editor, project, [:owner, :admin])
    end

    test "is false for a role-holding user who has not met the requirement" do
      user = insert(:user, mfa_enabled: false)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      refute Scope.role_in?(user, project, [:owner, :admin])
    end

    test "is true again once that user enrols" do
      user = insert(:user, mfa_enabled: true)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user_id: user.id, role: :admin}]
        )

      assert Scope.role_in?(user, project, [:owner, :admin])
    end

    test "is true for an operator on a live project, false on a scheduled one",
         %{live_project: live_project, scheduled_deleted_project: scheduled} do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      assert Scope.role_in?(account, live_project, [:owner])
      refute Scope.role_in?(account, scheduled, [:owner])
    end

    test "is false for a scheduled-deleted project", %{
      editor: editor,
      scheduled_deleted_project: project
    } do
      refute Scope.role_in?(editor, project, [:editor])
    end
  end

  describe "a repo connection as the actor" do
    test "resolves a live project with no role", %{live_project: project} do
      repo_connection = insert(:project_repo_connection, project: project)

      assert {:ok, scope} = Scope.fetch(repo_connection, project)
      assert scope.project.id == project.id
      assert scope.actor == repo_connection
      # No membership to look up — nil here means "no row", not "suppressed".
      assert scope.role == nil
      assert scope.project_user == nil
      assert scope.support? == false
    end

    # A machine credential cannot enrol, so the requirement does not apply to
    # it — and must not, or GitHub sync breaks the moment a project turns the
    # toggle on.
    test "meets the MFA requirement of a project that has one" do
      project = insert(:project, requires_mfa: true)
      repo_connection = insert(:project_repo_connection, project: project)

      assert {:ok, scope} = Scope.fetch(repo_connection, project)
      assert scope.mfa_satisfied? == true
    end

    test "sees its own scheduled-deleted project as scheduled", %{
      scheduled_deleted_project: project
    } do
      repo_connection = insert(:project_repo_connection, project: project)

      assert {:ok, %Scope{scheduled_for_deletion?: true}} =
               Scope.fetch(repo_connection, project)
    end

    test "cannot hide that with a hand-built project either", %{
      scheduled_deleted_project: project
    } do
      repo_connection = insert(:project_repo_connection, project: project)

      assert {:ok, %Scope{scheduled_for_deletion?: true}} =
               Scope.fetch(repo_connection, %Project{id: project.id})
    end

    test "gets no such project for an unknown id" do
      repo_connection = insert(:project_repo_connection)

      assert {:error, :no_such_project} =
               Scope.fetch(repo_connection, Ecto.UUID.generate())
    end

    # A connection's standing is which single project it belongs to. Refusing
    # here rather than at the call site stops a policy forgetting the
    # comparison.
    test "is refused a project it does not belong to", %{live_project: project} do
      other_project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: other_project)

      assert {:error, :connection_not_for_this_project} =
               Scope.fetch(repo_connection, project)
    end

    test "is refused another project by id, and by anything carrying its id", %{
      live_project: project
    } do
      other_project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: other_project)
      dataclip = insert(:dataclip, project: project)

      assert {:error, :connection_not_for_this_project} =
               Scope.fetch(repo_connection, project.id)

      assert {:error, :connection_not_for_this_project} =
               Scope.fetch(repo_connection, dataclip)
    end

    # A connection is refused someone else's project before it is told the
    # project's state, so it can't learn whether that project is being wound
    # down.
    test "learns nothing about the state of a project that is not its own", %{
      scheduled_deleted_project: project
    } do
      other_project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: other_project)

      assert {:error, :connection_not_for_this_project} =
               Scope.fetch(repo_connection, project)
    end
  end

  describe "a service account as the actor" do
    setup do
      {account, _private_key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      %{account: account}
    end

    test "resolves a live project by project, id, or membership row, with no role",
         %{account: account, live_project: project} do
      project_user =
        hd(Lightning.Repo.preload(project, :project_users).project_users)

      for subject <- [project, project.id, project_user] do
        assert {:ok, scope} = Scope.fetch(account, subject)
        assert scope.project.id == project.id
        assert scope.actor == account
        assert scope.instance_role == :operator
        assert scope.role == nil
        assert scope.project_user == nil
        assert scope.support? == false
      end
    end

    # A machine credential cannot enrol, so the requirement does not apply.
    test "meets the MFA requirement of a project that has one", %{
      account: account
    } do
      project = insert(:project, requires_mfa: true)

      assert {:ok, scope} = Scope.fetch(account, project)
      assert scope.mfa_satisfied? == true
    end

    test "sees a scheduled-deleted project as scheduled, same as a user", %{
      account: account,
      scheduled_deleted_project: project
    } do
      assert {:ok, %Scope{scheduled_for_deletion?: true}} =
               Scope.fetch(account, %Project{id: project.id})
    end

    test "gets no such project for an unknown or malformed id", %{
      account: account
    } do
      assert {:error, :no_such_project} =
               Scope.fetch(account, Ecto.UUID.generate())

      assert {:error, :no_such_project} = Scope.fetch(account, "not-a-uuid")
    end
  end
end
