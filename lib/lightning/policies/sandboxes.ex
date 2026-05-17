defmodule Lightning.Policies.Sandboxes do
  @moduledoc """
  The Bodyguard Policy module for sandbox project operations.

  A sandbox is an independent project with its own `project_users`
  membership. Authority is decided by the actor's role on the project
  involved in the action, never inherited from an ancestor and never
  granted by user type (the `:user`/`:superuser` enum has no bearing
  on public-surface authorization).

  ## Two-sided merge gate

  Merge has two distinct gates that must both hold for a merge to succeed:

    * **Source side**, enforced by `manage_authority/2` in this module
      (`:owner`/`:admin` on the source sandbox). Called from
      `SandboxLive.Index` when building each sandbox card so the Merge
      button can be disabled in the workspace list.

    * **Target side**, enforced by the `:merge_sandbox` clause of
      `authorize/3`  (`:editor`+ on the target project). Called from
      `SandboxLive.Index` when the user submits the merge form to
      confirm the target the user picked is one they can write into.

  The split exists because the two gates check different projects: the
  source side governs "can this user retire this sandbox" (it cascades
  the source's scheduled deletion through descendants), and the target
  side governs "can this user write changes into the target."
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
  Bulk manage-authority check for multiple sandboxes, avoiding N+1
  queries.

  Returns a map of `sandbox_id => boolean` where the boolean is `true`
  when `user` has `:owner` or `:admin` on that sandbox. That is the role
  required to update, delete, or merge it (and, by extension, to cancel
  a scheduled deletion).

  Each `sandbox.project_users` must be preloaded (as ensured by
  `Projects.list_workspace_projects/2`); the function raises
  `ArgumentError` otherwise.
  """
  @spec manage_authority([Project.t()], User.t()) :: %{binary() => boolean()}
  def manage_authority(sandboxes, %User{} = user) do
    Enum.each(sandboxes, &assert_project_users_loaded!/1)

    Map.new(sandboxes, fn sandbox ->
      can_manage? =
        Enum.any?(
          sandbox.project_users,
          &(&1.user_id == user.id and &1.role in [:owner, :admin])
        )

      {sandbox.id, can_manage?}
    end)
  end

  defp assert_project_users_loaded!(%Project{
         project_users: %Ecto.Association.NotLoaded{}
       }) do
    raise ArgumentError,
          "manage_authority/2 requires :project_users to be preloaded on " <>
            "every sandbox; see the function docstring"
  end

  defp assert_project_users_loaded!(%Project{}), do: :ok
end
