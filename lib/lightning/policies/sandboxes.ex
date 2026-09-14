defmodule Lightning.Policies.Sandboxes do
  @moduledoc """
  The Bodyguard Policy module for sandbox project operations.

  Sandbox authorization mirrors regular projects: access is decided by the
  acting user's role on the project they're acting on (or the workspace
  root, where the cascade applies). `User.role` (`:user` / `:superuser`)
  is a user-type for global user-management screens; it is not a
  project-access bypass and has no effect on sandbox policy decisions, in
  line with `Lightning.Policies.ProjectUsers`.

  - Sandbox owners/admins can manage their own sandboxes
  - Root project owners/admins can manage any sandbox in their workspace
  - Editors (and above) on the parent project can provision sandboxes

  Every action except provisioning and merging acts on a sandbox, and a
  workspace root is not one. A root is refused before any role is considered,
  which is what keeps the root cascade from admitting the root itself.

  Destructive actions on a sandbox (delete, update, merge) are scoped to
  admin/owner on the sandbox itself (or the root cascade above). This
  matches the rest of Lightning, where destructive actions are admin/owner
  scoped, and it keeps the merge button on the sandboxes list aligned with
  the cleanup step that runs after merge submission (which calls
  `:delete_sandbox` and so requires admin/owner on the source).
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.Scope

  @type actions ::
          :delete_sandbox
          | :update_sandbox
          | :provision_sandbox
          | :merge_sandbox
          | :cancel_scheduled_deletion

  # The only two actions whose subject is not the sandbox being acted on:
  # provisioning names the parent to build under, merging names the project to
  # merge into, and a workspace root is a legal value for both. Listing the
  # exceptions rather than the rule means a new action that nobody classifies is
  # refused on a root instead of admitted.
  @parent_subject_actions [:provision_sandbox, :merge_sandbox]

  @doc """
  Authorize sandbox operations based on the user's role on the project
  involved.

  ## Authorization Rules

  ### `:delete_sandbox`, `:update_sandbox` and `:cancel_scheduled_deletion`
  The subject must be a sandbox: a project with no parent is refused outright,
  whoever is asking. Beyond that the user must be one of:
  - Owner/admin of the sandbox itself
  - Owner/admin of the root project (workspace)

  ### `:provision_sandbox`
  User must be editor/admin/owner of the parent project they're creating
  the sandbox under.

  ### `:merge_sandbox`
  This check authorises the **target side** of a merge: the user must be
  editor/admin/owner on the target project (the project being merged
  *into*). The merge flow also requires admin/owner on the **source
  sandbox** itself, enforced by `manage_permissions/3` (button
  gate) and by the post-merge cleanup, which calls `:delete_sandbox`
  to retire the source and so requires admin/owner there.

  ### Support access
  No sandbox action honours it: every clause decides on `role` alone, so a
  support user with no membership row is refused even on a consenting project.
  Inherited behaviour, not a ruling.

  ## Parameters
  - `action` - The action being attempted
  - `user` - The user attempting the action
  - `project` - The sandbox project (for delete/update), parent project (for provision),
    or target project (for merge)
  """
  @spec authorize(actions(), User.t(), Project.t()) :: boolean

  # Answered here rather than in each clause below, so no sandbox action can
  # forget it. A workspace root is not a sandbox, however the caller reached it.
  # Without this the root cascade admits the root itself: `root_of/1` on a root
  # returns the root, so a root admin resolves as admin "on the sandbox" and
  # inherits a capability that `:delete_project` reserves for owners.
  def authorize(action, %User{}, %Project{parent_id: nil})
      when action not in @parent_subject_actions,
      do: false

  def authorize(:provision_sandbox, %User{} = user, %Project{} = parent_project) do
    Scope.role_in?(user, parent_project, [:owner, :admin, :editor])
  end

  def authorize(:merge_sandbox, %User{} = user, %Project{} = target_project) do
    Scope.role_in?(user, target_project, [:owner, :admin, :editor])
  end

  # The root cascade is a role rule, not a bypass: a root owner/admin counts as
  # admin *on this sandbox*, so the sandbox still has to be operable. Resolving
  # it first keeps the cascade unreachable for a sandbox scheduled for deletion.
  #
  # Only this branch reads `role` off the Scope directly, so only it needs the
  # MFA fact spelled out; has_root_project_permission?/2 gets the same guard for
  # free from Scope.role_in?/3.
  def authorize(action, %User{} = user, %Project{} = sandbox)
      when action in [:delete_sandbox, :update_sandbox] do
    case Scope.fetch(user, sandbox) do
      {:ok, %Scope{role: role, mfa_satisfied?: mfa}} ->
        (role in [:owner, :admin] and mfa) or
          has_root_project_permission?(sandbox, user)

      {:error, _reason} ->
        false
    end
  end

  # Deliberately does not go through Scope: the subject is scheduled for
  # deletion by definition, and Scope refuses those, so the liveness gate would
  # make a sandbox scheduled for deletion impossible to restore. Same role rule as
  # :delete_sandbox, read directly.
  def authorize(:cancel_scheduled_deletion, %User{} = user, %Project{} = sandbox) do
    root_project = Projects.root_of(sandbox)

    Projects.get_project_user_role(user, sandbox) in [:owner, :admin] or
      Projects.get_project_user_role(user, root_project) in [:owner, :admin]
  end

  def authorize(_action, _user, _project), do: false

  @doc """
  Bulk manage check for multiple sandboxes, avoiding N+1 queries.

  Returns a map `sandbox_id => boolean()` where `true` means the user can
  perform the destructive actions the sandbox list offers on that row: they are
  an owner/admin on the sandbox itself, or an owner/admin on the root project
  (cascade). The workspace root is always `false`, which is what the list relies
  on to withhold edit, delete and merge from the root. Note this is the merge
  *source* side; `:merge_sandbox` authorises the target and a root is a legal
  target.

  Assumes `root_project.project_users` and each `sandbox.project_users`
  are preloaded (as ensured by `Projects.list_workspace_projects/2`).

  Reads those preloaded rows rather than resolving a `Scope`, so it does not
  hold the actor to the project's MFA requirement. Nothing reaches it that has
  not already been held to it: the list it feeds mounts
  `LightningWeb.Hooks.:project_scope`, which redirects an unenrolled member to
  `/mfa_required` before the page renders, and every action a `true` enables
  refuses on its own.
  """
  @spec manage_permissions([Project.t()], User.t(), Project.t()) ::
          %{binary() => boolean()}
  def manage_permissions(sandboxes, %User{} = user, root_project) do
    root_admin? = owner_or_admin?(root_project, user)

    # The list this feeds includes the workspace root, and the root is not a
    # sandbox, so it is never manageable through a sandbox action.
    Map.new(sandboxes, fn sandbox ->
      {sandbox.id,
       Project.sandbox?(sandbox) and
         (root_admin? or owner_or_admin?(sandbox, user))}
    end)
  end

  # Read from preloaded rows rather than the database, because this runs over a
  # whole workspace at once.
  defp owner_or_admin?(%Project{} = project, %User{id: user_id}) do
    Enum.any?(
      project.project_users,
      &(&1.user_id == user_id and &1.role in [:owner, :admin])
    )
  end

  defp has_root_project_permission?(%Project{} = sandbox, %User{} = user) do
    root_project = Projects.root_of(sandbox)
    Scope.role_in?(user, root_project, [:owner, :admin])
  end
end
