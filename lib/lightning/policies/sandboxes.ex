defmodule Lightning.Policies.Sandboxes do
  @moduledoc """
  The Bodyguard Policy module for sandbox project operations.

  A sandbox is an independent project with its own `project_users`
  membership. Authority is decided by the actor's role on the project
  involved in the action, never inherited from an ancestor and never
  granted by user type (the `:user`/`:superuser` enum has no bearing
  on public-surface authorization).
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project

  @type actions ::
          :delete_sandbox
          | :update_sandbox
          | :provision_sandbox
          | :merge_sandbox

  @doc """
  Authorize sandbox operations based on the actor's role on the project
  involved.

  ## Authorization Rules

  ### `:delete_sandbox` and `:update_sandbox`
  User must be `:owner` or `:admin` of the sandbox itself.

  ### `:provision_sandbox`
  User must be `:editor`, `:admin`, or `:owner` of the parent project
  they are creating the sandbox under.

  ### `:merge_sandbox`
  User must be `:editor`, `:admin`, or `:owner` on the target project.

  ## Parameters
  - `action` - The action being attempted
  - `user` - The user attempting the action
  - `project` - The sandbox project (for delete/update), parent project (for provision),
    or target project (for merge)
  """
  @spec authorize(actions(), User.t(), Project.t()) :: boolean

  def authorize(:provision_sandbox, %User{} = user, %Project{} = parent_project) do
    Projects.get_project_user_role(user, parent_project) in [
      :owner,
      :admin,
      :editor
    ]
  end

  def authorize(:merge_sandbox, %User{} = user, %Project{} = target_project) do
    Projects.get_project_user_role(user, target_project) in [
      :owner,
      :admin,
      :editor
    ]
  end

  def authorize(action, %User{} = user, %Project{} = sandbox)
      when action in [:delete_sandbox, :update_sandbox] do
    Projects.get_project_user_role(user, sandbox) in [:owner, :admin]
  end

  def authorize(_action, _user, _project), do: false

  @doc """
  Bulk permission check for multiple sandboxes to avoid N+1 queries.

  Returns a map: sandbox_id => %{update: boolean, delete: boolean, merge: boolean}

  Assumes each `sandbox.project_users` is preloaded (as ensured by
  `Projects.list_workspace_projects/2`).
  """
  @spec check_manage_permissions([Project.t()], User.t(), Project.t()) ::
          %{
            binary() => %{update: boolean(), delete: boolean(), merge: boolean()}
          }
  def check_manage_permissions(sandboxes, %User{} = user, _root_project) do
    Map.new(sandboxes, fn sandbox ->
      is_owner_or_admin_here? =
        Enum.any?(
          sandbox.project_users,
          &(&1.user_id == user.id and &1.role in [:owner, :admin])
        )

      {sandbox.id,
       %{
         update: is_owner_or_admin_here?,
         delete: is_owner_or_admin_here?,
         merge: is_owner_or_admin_here?
       }}
    end)
  end
end
