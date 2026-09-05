defmodule Lightning.Policies.ProjectUserPermissionsTest do
  @moduledoc """
  Project user permissions determine what a user can and cannot do within a
  project. Projects (i.e., "workspaces") can have multiple collaborators with
  varying levels of access to the resources (workflows, jobs, triggers, runs)
  within.

  The tests ensure both that user "Amy" that has been added as an `editor` for project "X",
  _can_ view and edit jobs (for example) in project X, and that they _cannot_ view and edit jobs in project Y.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Accounts
  alias Lightning.Policies.{Permissions, ProjectUsers}
  alias Lightning.Projects.Scope

  @project_user_actions ~w(
    create_workflow
    edit_workflow
    delete_workflow
    run_workflow
    create_project_credential
    initiate_github_sync
    create_channel
    delete_channel
    update_channel
  )a

  setup do
    viewer = insert(:user)
    admin = insert(:user)
    owner = insert(:user)
    editor = insert(:user)
    intruder = insert(:user)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    project =
      insert(:project,
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ]
      )

    marked_project =
      insert(:project,
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ],
        scheduled_deletion: now
      )

    %{
      project: project,
      marked_project: marked_project,
      viewer: viewer,
      admin: admin,
      owner: owner,
      editor: editor,
      intruder: intruder
    }
  end

  describe "Users that are not members to a project" do
    test "cannot access that project", %{project: project, intruder: intruder} do
      refute ProjectUsers |> Permissions.can?(:access_project, intruder, project)
    end
  end

  describe "Members of a project (viewer, editor, admin or owner)" do
    test "can access that project", %{
      project: project,
      viewer: viewer
    } do
      assert ProjectUsers |> Permissions.can?(:access_project, viewer, project)
    end

    test "can not access a project that is scheduled for deletion", %{
      marked_project: marked_project,
      viewer: viewer
    } do
      refute ProjectUsers
             |> Permissions.can?(:access_project, viewer, marked_project)
    end

    test "can edit their own digest and failure alerts for that project",
         %{project: project} do
      project_user_1 = project.project_users |> Enum.at(0)
      user_1 = Accounts.get_user!(project_user_1.user_id)

      ~w(
        edit_digest_alerts
        edit_failure_alerts
      )a |> (&assert_can(ProjectUsers, &1, user_1, project_user_1)).()
    end

    test "cannot edit other members digest and failure alerts",
         %{project: project} do
      project_user_1 = project.project_users |> Enum.at(0)
      project_user_2 = project.project_users |> Enum.at(1)
      user_1 = Accounts.get_user!(project_user_1.user_id)

      ~w(
        edit_digest_alerts
        edit_failure_alerts
      )a |> (&refute_can(ProjectUsers, &1, user_1, project_user_2)).()
    end

    # A %Project{} subject never carries a client-supplied project_user_id, so
    # there is no "whose row is this" question to answer — Scope already
    # resolved it to the caller's own standing. This goes through `permitted?`
    # rather than the id == user_id clause above.
    test "can edit their own digest and failure alerts given only the project",
         %{project: project, editor: editor} do
      ~w(
        edit_digest_alerts
        edit_failure_alerts
      )a |> (&assert_can(ProjectUsers, &1, editor, project)).()
    end

    test "cannot edit digest and failure alerts given only the project without a membership row",
         %{project: project, intruder: intruder} do
      ~w(
        edit_digest_alerts
        edit_failure_alerts
      )a |> (&refute_can(ProjectUsers, &1, intruder, project)).()
    end
  end

  describe "Project users with the :viewer role" do
    test "cannot create / delete workflows, create / edit / run / rerun jobs, and edit the project name or description",
         %{
           project: project,
           viewer: viewer
         } do
      ~w(
        create_workflow
        delete_workflow
        edit_workflow
        edit_project
        write_webhook_auth_method
        create_project_credential
        run_workflow
      )a |> (&refute_can(ProjectUsers, &1, viewer, project)).()
    end
  end

  describe "Project users with the :editor role" do
    test "can create / delete workflows and create / edit / run / rerun jobs in the project",
         %{
           project: project,
           editor: editor
         } do
      ~w(
        create_workflow
        delete_workflow
        edit_workflow
        create_project_credential
        run_workflow
      )a |> (&assert_can(ProjectUsers, &1, editor, project)).()
    end

    test "cannot edit the project name, and edit the project description",
         %{
           project: project,
           editor: editor
         } do
      ~w(
          edit_project
          write_webhook_auth_method
        )a |> (&refute_can(ProjectUsers, &1, editor, project)).()
    end
  end

  describe "Project users with the :admin role" do
    test "can create / delete workflows, create / edit / run / rerun jobs, edit the project name, and edit the project description.",
         %{
           project: project,
           admin: admin
         } do
      ~w(
          create_workflow
          delete_workflow
          edit_workflow
          edit_project
          write_webhook_auth_method
          create_project_credential
          run_workflow
        )a |> (&assert_can(ProjectUsers, &1, admin, project)).()
    end
  end

  describe "Project users with the :owner role" do
    test "can create / delete workflows, create / edit / run / rerun jobs, edit the project name, and edit the project description.",
         %{
           project: project,
           owner: owner
         } do
      ~w(
        create_workflow
        delete_workflow
        edit_workflow
        edit_project
        write_webhook_auth_method
        create_project_credential
        run_workflow
      )a |> (&assert_can(ProjectUsers, &1, owner, project)).()
    end
  end

  describe "Support users" do
    test "can access projects that allow support access", %{project: project} do
      support_user = insert(:user, support_user: true)
      project = with_support_access(project, true)

      assert ProjectUsers
             |> Permissions.can?(:access_project, support_user, project)
    end

    test "cannot access projects that don't allow support access", %{
      project: project
    } do
      support_user = insert(:user, support_user: true)
      project = with_support_access(project, false)

      refute ProjectUsers
             |> Permissions.can?(:access_project, support_user, project)
    end

    test "have the same worfklow allowance as editor on a project that allows support access",
         %{project: project} do
      support_user = insert(:user, support_user: true)

      editor_project_user =
        insert(:project_user,
          project: project,
          user: build(:user),
          role: :editor
        )

      assert_can(
        ProjectUsers,
        @project_user_actions,
        support_user,
        with_support_access(project, true)
      )

      assert_can(
        ProjectUsers,
        @project_user_actions,
        editor_project_user.user,
        editor_project_user
      )
    end

    test "cannot perform project user actions on a project that denies support access",
         %{project: project} do
      support_user = insert(:user, support_user: true)

      refute_can(
        ProjectUsers,
        @project_user_actions,
        support_user,
        with_support_access(project, false)
      )
    end

    test "cannot perform project user actions when pinned to a viewer role",
         %{project: project} do
      support_user = insert(:user, support_user: true)

      insert(:project_user, project: project, user: support_user, role: :viewer)

      for allow_support_access <- [true, false] do
        refute_can(
          ProjectUsers,
          @project_user_actions,
          support_user,
          with_support_access(project, allow_support_access)
        )
      end
    end

    test "cannot perform project user actions when not a support user", %{
      project: project
    } do
      regular_user = insert(:user, support_user: false)

      refute_can(ProjectUsers, @project_user_actions, regular_user, nil)

      refute_can(
        ProjectUsers,
        @project_user_actions,
        regular_user,
        with_support_access(project, true)
      )
    end

    test "cannot perform project user actions given only a missing membership row",
         %{project: _project} do
      support_user = insert(:user, support_user: true)

      refute_can(ProjectUsers, @project_user_actions, support_user, nil)
    end

    test "can publish template when project member", %{project: project} do
      support_user = insert(:user, support_user: true)
      insert(:project_user, project: project, user: support_user, role: :editor)

      assert ProjectUsers
             |> Permissions.can?(:publish_template, support_user, project)
    end

    test "can publish template with support access enabled", %{
      project: project
    } do
      support_user = insert(:user, support_user: true)
      project = with_support_access(project, true)

      assert ProjectUsers
             |> Permissions.can?(:publish_template, support_user, project)
    end

    test "cannot publish template without project membership and support access disabled",
         %{project: project} do
      support_user = insert(:user, support_user: true)
      project = with_support_access(project, false)

      refute ProjectUsers
             |> Permissions.can?(:publish_template, support_user, project)
    end

    test "non-support user cannot publish template even if project member",
         %{project: project} do
      regular_user = insert(:user, support_user: false)
      insert(:project_user, project: project, user: regular_user, role: :editor)

      refute ProjectUsers
             |> Permissions.can?(:publish_template, regular_user, project)
    end
  end

  # Requiring MFA removes no membership rows either, so — as with a scheduled
  # deletion — every role below still holds a real project_users row and the
  # refusal has to come from the policy layer. The users in `setup` are all
  # unenrolled: `mfa_enabled` defaults to false.
  describe "a project that requires MFA, for an unenrolled member" do
    @roles [:viewer, :editor, :admin, :owner]

    setup context do
      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users:
            Enum.map(@roles, fn role ->
              %{user_id: context[role].id, role: role}
            end)
        )

      %{mfa_project: mfa_project}
    end

    test "refuses every action this policy decides, for every role", context do
      %{mfa_project: mfa_project} = context

      actions = ProjectUsers.actions()

      # Same reasoning as the scheduled-deletion sweep: enumerating from the
      # module covers an action added tomorrow, and the named action stops the
      # comprehension going quietly vacuous if `actions/0` ever returns [].
      assert :create_workflow in actions

      allowed =
        for action <- actions,
            role <- @roles,
            Permissions.can?(ProjectUsers, action, context[role], mfa_project) do
          "#{action}/:#{role}"
        end

      assert allowed == [],
             "these actions were ALLOWED to a member who has not enrolled in " <>
               "MFA: " <> Enum.join(allowed, ", ")
    end

    # The sweep above passes a project, so it never reaches the clause that
    # takes a `%ProjectUser{}`. That clause does not call permitted?/2 at all,
    # so it needs — and has — its own MFA check.
    test "refuses every action when the subject is the member's own row",
         context do
      actions = ProjectUsers.actions()
      assert :edit_digest_alerts in actions

      own_rows =
        Map.new(@roles, fn role ->
          user = context[role]

          row =
            Enum.find(
              context.mfa_project.project_users,
              &(&1.user_id == user.id)
            )

          assert row,
                 "no membership row for :#{role} — the sweep below would be " <>
                   "checking nothing"

          {role, row}
        end)

      allowed =
        for action <- actions,
            role <- @roles,
            Permissions.can?(ProjectUsers, action, context[role], own_rows[role]) do
          "#{action}/:#{role}"
        end

      assert allowed == [],
             "these actions were ALLOWED against the member's own row on an " <>
               "MFA-required project: " <> Enum.join(allowed, ", ")
    end

    # Without this, both sweeps above would pass just as happily against a
    # policy that refused everyone everything.
    test "allows the same actions once the member enrols", %{
      mfa_project: mfa_project
    } do
      enrolled = insert(:user, mfa_enabled: true)

      project_user =
        insert(:project_user,
          project: mfa_project,
          user: enrolled,
          role: :admin
        )

      assert_can(ProjectUsers, :access_project, enrolled, mfa_project)
      assert_can(ProjectUsers, @project_user_actions, enrolled, mfa_project)
      assert_can(ProjectUsers, :edit_project, enrolled, mfa_project)
      assert_can(ProjectUsers, :edit_digest_alerts, enrolled, project_user)
    end

    # A support user is a human reading project data, so the requirement binds
    # them on the same terms as a member.
    test "refuses a support user on a consenting project", %{
      mfa_project: mfa_project
    } do
      support_user = insert(:user, support_user: true)
      mfa_project = with_support_access(mfa_project, true)

      refute_can(ProjectUsers, :access_project, support_user, mfa_project)
      refute_can(ProjectUsers, @project_user_actions, support_user, mfa_project)
    end
  end

  describe "blocked_by_mfa?/1" do
    setup %{editor: editor} do
      enrolled = insert(:user, mfa_enabled: true)

      # Both projects require MFA; support consent is the axis between them, so
      # it is written out on each rather than left to the schema default.
      mfa_project =
        insert(:project,
          requires_mfa: true,
          allow_support_access: false,
          project_users: [
            %{user_id: editor.id, role: :editor},
            %{user_id: enrolled.id, role: :editor}
          ]
        )

      consenting_project =
        insert(:project, requires_mfa: true, allow_support_access: true)

      %{
        mfa_project: mfa_project,
        consenting_project: consenting_project,
        enrolled: enrolled
      }
    end

    # The paired `permitted?(:access_project, ...)` answer is what gives the
    # predicate its meaning: an unenrolled member is refused but blocked, while
    # a stranger is refused and not blocked. Only the first may be sent to
    # `/mfa_required`, which tells whoever asked that the project exists and how
    # it is configured; a stranger has to get not-found instead. Support access
    # is what gives a support user standing at all, so without it they are the
    # stranger, not the blocked member.
    test "answers true only for an actor with standing who has not enrolled",
         %{
           editor: editor,
           enrolled: enrolled,
           intruder: intruder,
           project: project,
           mfa_project: mfa_project,
           consenting_project: consenting_project
         } do
      support_user = insert(:user, support_user: true)

      rows = [
        {"a member who has not enrolled", editor, mfa_project, true, false},
        {"a member who has enrolled", enrolled, mfa_project, false, true},
        {"someone with no standing at all", intruder, mfa_project, false, false},
        {"an unenrolled support user on a consenting project", support_user,
         consenting_project, true, false},
        {"a support user the project has not consented to", support_user,
         mfa_project, false, false},
        {"a member on a project that does not require MFA", editor, project,
         false, true}
      ]

      for {label, actor, subject, blocked?, access?} <- rows do
        scope =
          case Scope.fetch(actor, subject) do
            {:ok, scope} -> scope
            error -> flunk("no scope for #{label}: #{inspect(error)}")
          end

        assert ProjectUsers.blocked_by_mfa?(scope) == blocked?,
               "blocked_by_mfa?/1 should answer #{blocked?} for #{label}"

        assert ProjectUsers.permitted?(:access_project, scope) == access?,
               "permitted?(:access_project, ...) should answer #{access?} " <>
                 "for #{label}"
      end
    end
  end

  # Scheduling deletion removes no membership rows
  # (`Projects.scheduled_project_deletion_changes/2`), so each role below still
  # holds a real project_users row on the shut-down project. The refusal has to
  # come from the policy layer, because nothing else has taken these people's
  # standing away.
  describe "a project scheduled for deletion" do
    @roles [:viewer, :editor, :admin, :owner]

    test "refuses every action this policy decides, for every role", context do
      %{marked_project: marked_project} = context

      actions = ProjectUsers.actions()

      # Enumerating from the module is the point: an action added tomorrow is
      # covered tomorrow, not whenever someone remembers this file. It is also
      # how the test could go quietly vacuous — an `actions/0` returning `[]`
      # empties the comprehension and passes having checked nothing. Named
      # action rather than a count, because a count is a number someone bumps
      # without reading.
      assert :create_workflow in actions

      # Collected rather than asserted one at a time, so a failure names every
      # action/role pair that gets through, not just the first.
      allowed =
        for action <- actions,
            role <- @roles,
            Permissions.can?(ProjectUsers, action, context[role], marked_project) do
          "#{action}/:#{role}"
        end

      assert allowed == [],
             "these actions were ALLOWED on a project scheduled for deletion: " <>
               Enum.join(allowed, ", ")
    end

    # The sweep above passes a project, so it never reaches the clause that
    # takes a `%ProjectUser{}` — the one asking "is this row mine" rather than
    # "what standing do I have here". That is the shape project settings calls
    # with, and it consults Scope for the project too, so a wound-down project
    # refuses even your own notification preferences.
    test "refuses every action when the subject is the member's own row",
         context do
      actions = ProjectUsers.actions()
      assert :edit_digest_alerts in actions

      own_rows =
        Map.new(@roles, fn role ->
          user = context[role]

          row =
            Enum.find(
              context.marked_project.project_users,
              &(&1.user_id == user.id)
            )

          assert row,
                 "no membership row for :#{role} — the sweep below would be " <>
                   "checking nothing"

          {role, row}
        end)

      allowed =
        for action <- actions,
            role <- @roles,
            Permissions.can?(ProjectUsers, action, context[role], own_rows[role]) do
          "#{action}/:#{role}"
        end

      assert allowed == [],
             "these actions were ALLOWED against a member's own row on a " <>
               "project scheduled for deletion: " <> Enum.join(allowed, ", ")
    end

    test "refuses :delete_project for the owner", context do
      refute_scheduled(
        :delete_project,
        context.owner,
        context.marked_project,
        :owner
      )
    end

    test "refuses :publish_template for a support user who is a member",
         context do
      support_user = insert(:user, support_user: true)

      insert(:project_user,
        project: context.marked_project,
        user: support_user,
        role: :editor
      )

      refute_scheduled(
        :publish_template,
        support_user,
        context.marked_project,
        :editor
      )
    end
  end

  # Persisted, not set on the struct in passing: support access is a stored
  # containment control, and Scope reads it from the row. A policy that could be
  # satisfied by a field assigned in the caller would not be a control at all.
  defp with_support_access(project, allowed) do
    project
    |> Ecto.Changeset.change(allow_support_access: allowed)
    |> Lightning.Repo.update!()
  end

  defp refute_scheduled(action, user, project, role) do
    refute Permissions.can?(ProjectUsers, action, user, project),
           "expected #{action} to be REFUSED for a :#{role} on project " <>
             "#{project.id}, which is scheduled for deletion"
  end

  defp assert_can(module, actions, user, subject) when is_list(actions) do
    Enum.each(actions, &assert_can(module, &1, user, subject))
  end

  defp assert_can(module, action, user, subject) when is_atom(action) do
    assert module |> Permissions.can?(action, user, subject)
  end

  defp refute_can(module, actions, user, subject) when is_list(actions) do
    Enum.each(actions, &refute_can(module, &1, user, subject))
  end

  defp refute_can(module, action, user, subject) when is_atom(action) do
    refute module |> Permissions.can?(action, user, subject)
  end
end
