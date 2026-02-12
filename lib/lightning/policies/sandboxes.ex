defmodule Lightning.Policies.Sandboxes do
  @moduledoc """
  The Bodyguard Policy module for sandbox project operations.

  Sandboxes have different authorization rules than regular projects:
  - Sandbox owners/admins can manage their own sandboxes
  - Root project owners/admins can manage any sandbox in their workspace
  - Editors (and above) on the root project can merge sandboxes
  - Editors (and above) on the parent project can provision sandboxes
  - Superusers can manage any sandbox anywhere
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
  Authorize sandbox operations based on user role and project hierarchy.

  ## Authorization Rules

  ### `:delete_sandbox` and `:update_sandbox`
  User can perform these actions if they are:
  - Superuser (can manage any sandbox)
  - Owner/admin of the sandbox itself
  - Owner/admin of the root project (workspace)

  ### `:provision_sandbox`
  User can create sandboxes if they are:
  - Editor/admin/owner of the parent project they're creating the sandbox under

  ### `:merge_sandbox`
  User can merge a sandbox into a target project if they are:
  - Editor/admin/owner on the target project
  - Superuser

  ## Parameters
  - `action` - The action being attempted
  - `user` - The user attempting the action
  - `project` - The sandbox project (for delete/update), parent project (for provision),
    or target project (for merge)
  """
  @spec authorize(actions(), User.t(), Project.t()) :: boolean

  def authorize(:provision_sandbox, %User{} = user, %Project{} = parent_project) do
    case Projects.get_project_user_role(user, parent_project) do
      role when role in [:owner, :admin, :editor] -> true
      _ -> user.role == :superuser
    end
  end

  def authorize(:merge_sandbox, %User{} = user, %Project{} = target_project) do
    case Projects.get_project_user_role(user, target_project) do
      role when role in [:owner, :admin, :editor] -> true
      _ -> user.role == :superuser
    end
  end

  def authorize(action, %User{} = user, %Project{} = sandbox)
      when action in [:delete_sandbox, :update_sandbox] do
    cond do
      user.role == :superuser ->
        true

      Projects.get_project_user_role(user, sandbox) in [:owner, :admin] ->
        true

      has_root_project_permission?(sandbox, user) ->
        true

      true ->
        false
    end
  end

  def authorize(_action, _user, _project), do: false

  @doc """
  Bulk permission check for multiple sandboxes to avoid N+1 queries.

  Returns a map: sandbox_id => %{update: boolean, delete: boolean, merge: boolean}

  Assumes `root_project.project_users` and each `sandbox.project_users`
  are preloaded (as ensured by `Projects.list_workspace_projects/2`).
  """
  @spec check_manage_permissions([Project.t()], User.t(), Project.t()) ::
          %{
            binary() => %{update: boolean(), delete: boolean(), merge: boolean()}
          }
  def check_manage_permissions(sandboxes, %User{} = user, root_project) do
    is_superuser = user.role == :superuser

    is_root_owner_or_admin =
      Enum.any?(
        root_project.project_users,
        &(&1.user_id == user.id and &1.role in [:owner, :admin])
      )

    is_root_editor_plus =
      Enum.any?(
        root_project.project_users,
        &(&1.user_id == user.id and &1.role in [:owner, :admin, :editor])
      )

    has_full_privileges = is_superuser or is_root_owner_or_admin

    if has_full_privileges do
      Map.new(sandboxes, &{&1.id, %{update: true, delete: true, merge: true}})
    else
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
           merge: is_superuser or is_root_editor_plus
         }}
      end)
    end
  end

  defp has_root_project_permission?(%Project{} = sandbox, %User{} = user) do
    root_project = Projects.root_of(sandbox)

    case Projects.get_project_user_role(user, root_project) do
      role when role in [:owner, :admin] -> true
      _ -> false
    end
  end
end
