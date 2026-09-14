defmodule Lightning.Projects.ScopeTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Project
  alias Lightning.Projects.Scope

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

  test "a scheduled-deleted project yields no scope, and says why", %{
    editor: editor,
    scheduled_deleted_project: project
  } do
    assert {:error, :project_scheduled_for_deletion} =
             Scope.fetch(editor, project)
  end

  test "a hand-built project struct cannot assert its own liveness", %{
    editor: editor,
    scheduled_deleted_project: project
  } do
    # scheduled_deletion is nil on this struct because nothing read it. Without
    # the reload it would pass a liveness check.
    fake = %Project{id: project.id}

    assert {:error, :project_scheduled_for_deletion} = Scope.fetch(editor, fake)
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

    test "a support user is refused a scheduled-deleted project outright" do
      support_user = insert(:user, support_user: true)

      project =
        insert(:project,
          allow_support_access: true,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:error, :project_scheduled_for_deletion} =
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
    # `build/2` should refuse, not silently pass.
    test "defaults to false on a scope that never went through build/2" do
      assert %Scope{}.mfa_satisfied? == false
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

    test "is refused a scheduled-deleted project, same as a user", %{
      scheduled_deleted_project: project
    } do
      repo_connection = insert(:project_repo_connection, project: project)

      assert {:error, :project_scheduled_for_deletion} =
               Scope.fetch(repo_connection, project)
    end

    test "cannot assert liveness with a hand-built project either", %{
      scheduled_deleted_project: project
    } do
      repo_connection = insert(:project_repo_connection, project: project)

      assert {:error, :project_scheduled_for_deletion} =
               Scope.fetch(repo_connection, %Project{id: project.id})
    end

    test "gets no such project for an unknown id" do
      repo_connection = insert(:project_repo_connection)

      assert {:error, :no_such_project} =
               Scope.fetch(repo_connection, Ecto.UUID.generate())
    end

    # A connection's standing is which single project it belongs to. Refusing
    # here rather than at the call site is what stops a policy forgetting the
    # comparison — the same reason a shut-down project yields no scope.
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

    # Ownership is checked before liveness so that a connection cannot learn
    # whether an unrelated project is being wound down. If this assertion ever
    # reads :project_scheduled_for_deletion, the `with` clauses in fetch/2 have
    # been reordered and a third party's state is leaking to a stranger.
    test "learns nothing about the state of a project that is not its own", %{
      scheduled_deleted_project: project
    } do
      other_project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: other_project)

      assert {:error, :connection_not_for_this_project} =
               Scope.fetch(repo_connection, project)
    end
  end
end
