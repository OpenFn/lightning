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

  @doc """
  Authorize sandbox operations based on the user's role on the project
  involved.

  ## Authorization Rules

  ### `:delete_sandbox` and `:update_sandbox`
  User must be one of:
  - Owner/admin of the sandbox itself
  - Owner/admin of the root project (workspace)

  ### `:provision_sandbox`
  User must be editor/admin/owner of the parent project they're creating
  the sandbox under.

  ### `:merge_sandbox`
  This check authorises the **target side** of a merge: the user must be
  editor/admin/owner on the target project (the project being merged
  *into*). The merge flow also requires admin/owner on the **source
  sandbox** itself, enforced by `check_manage_permissions/3` (button
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

  def authorize(:provision_sandbox, %User{} = user, %Project{} = parent_project) do
    Scope.role_in?(user, parent_project, [:owner, :admin, :editor])
  end

  def authorize(:merge_sandbox, %User{} = user, %Project{} = target_project) do
    Scope.role_in?(user, target_project, [:owner, :admin, :editor])
  end

  # The root cascade is a role rule, not a bypass: a root owner/admin counts as
  # admin *on this sandbox*, so the sandbox still has to be operable. Resolving
  # it first keeps the cascade unreachable for a sandbox scheduled for deletion.
  def authorize(action, %User{} = user, %Project{} = sandbox)
      when action in [:delete_sandbox, :update_sandbox] do
    case Scope.fetch(user, sandbox) do
      {:ok, %Scope{role: role}} ->
        role in [:owner, :admin] or has_root_project_permission?(sandbox, user)

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
  perform any of the destructive sandbox actions (update, delete, merge)
  on that sandbox. The boolean is `true` when the user is an owner/admin
  on the sandbox itself, or an owner/admin on the root project (cascade).

  Assumes `root_project.project_users` and each `sandbox.project_users`
  are preloaded (as ensured by `Projects.list_workspace_projects/2`).
  """
  @spec check_manage_permissions([Project.t()], User.t(), Project.t()) ::
          %{binary() => boolean()}
  def check_manage_permissions(sandboxes, %User{} = user, root_project) do
    is_root_owner_or_admin =
      Enum.any?(
        root_project.project_users,
        &(&1.user_id == user.id and &1.role in [:owner, :admin])
      )

    if is_root_owner_or_admin do
      Map.new(sandboxes, &{&1.id, true})
    else
      Map.new(sandboxes, fn sandbox ->
        can_manage? =
          Enum.any?(
            sandbox.project_users,
            &(&1.user_id == user.id and &1.role in [:owner, :admin])
          )

        {sandbox.id, can_manage?}
      end)
    end
  end

  defp has_root_project_permission?(%Project{} = sandbox, %User{} = user) do
    root_project = Projects.root_of(sandbox)
    Scope.role_in?(user, root_project, [:owner, :admin])
  end
end
