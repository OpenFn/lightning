defmodule Lightning.Policies.Permissions do
  @moduledoc """
  This module defines a unique interface managing authorizations in Lightning.

  Users in Lightning have instance-wide and project-wide roles which determine 
  their level of access to resources in the application. For more details see 
  the [documentation](https://docs.openfn.org/documentation/about-lightning#roles-and-permissions).

  ## Policy Modules

  Authorization policies are implemented under `lib/lightning/policies/`:
  - `users.ex` - Instance-wide access levels
  - `project_users.ex` - Project-wide access levels  
  - `credentials.ex` - Credential management permissions
  - `workflows.ex` - Workflow-related permissions
  - `collections.ex` - Collection access permissions
  - `dataclips.ex` - Dataclip permissions
  - `exports.ex` - Export functionality permissions
  - `provisioning.ex` - Resource provisioning permissions

  ## Interface

  This module provides the `can/4` and `can?/4` interface, which wraps 
  `Bodyguard.permit/4` to harmonize policy usage across the application.

  **Policy Resolution**: You can reference policy modules in two ways:
  - Full module names: `Lightning.Policies.Users`
  - Atom shortcuts for sub-modules: `:users`, `:project_users`, `:credentials`

  ## Functions

  - `can(policy, action, actor, resource)` - Returns `:ok` or `{:error, :unauthorized}`
  - `can?(policy, action, actor, resource)` - Returns `true` or `false`

  ## Examples

  **Using full module names:**
  ```elixir
  can_edit = Lightning.Policies.ProjectUsers 
             |> Lightning.Policies.Permissions.can?(:edit_workflow, user, project)
  ```

  **Using atom shortcuts:**
  ```elixir  
  can_create = Permissions.can?(:credentials, :create_keychain_credential, user, project)
  can_delete = Permissions.can?(:project_users, :delete_project, user, project)
  ```

  All policies are comprehensively tested in `test/lightning/policies/`.
  """

  @doc """
  checks if user has the permissions to apply action using some policy module

  Returns `:ok` if user can apply action and `{:error, :unauthorized}` otherwise

  ## Examples

      iex> can(Lightning.Policies.Users, :create_workflow, user, project)
      :ok

      iex> can(Lightning.Policies.Users, :create_project, user, %{})
      {:error, :unauthorized}

  """
  def can(policy, action, user, params \\ []) do
    policy
    |> resolve_policy_module()
    |> Bodyguard.permit(action, user, params)
  end

  @doc """
  same as can/4 but returns `true` if user can apply action and `false` otherwise

  ## Examples

      iex> can(Lightning.Policies.Users, :create_workflow, user, project)
      true

      iex> can(Lightning.Policies.Users, :create_project, user, %{})
      false

  """
  def can?(policy, action, user, params \\ []) do
    policy
    |> resolve_policy_module()
    |> Bodyguard.permit?(action, user, params)
  end

  @doc """
  Whether the caller described by `scope` may apply `action` to `subject`.

  The one entry point for API callers. Unlike `can/4`, a refusal is
  `{:error, :forbidden}`, so it renders as 403 rather than 401, and a policy's
  more specific answer (`:insufficient_scope`, `:scheduled_for_deletion`)
  reaches the caller unchanged.
  """
  @spec permit(atom(), atom(), Lightning.Scope.t(), term()) ::
          :ok
          | {:error, :forbidden | :insufficient_scope | :scheduled_for_deletion}
  def permit(policy, action, %Lightning.Scope{} = scope, subject) do
    case can(policy, action, scope, subject) do
      {:error, :unauthorized} -> {:error, :forbidden}
      result -> result
    end
  end

  @doc """
  Whether the caller's grant already refuses `action`, before any target is
  loaded. A pass here is not permission. The action still has to ask
  `permit/4` about its target.
  """
  @spec permit(atom(), atom(), Lightning.Scope.t()) ::
          :ok
          | {:error, :forbidden | :insufficient_scope | :scheduled_for_deletion}
  def permit(policy, action, %Lightning.Scope{} = scope),
    do: permit(policy, action, scope, :before_target)

  @doc """
  Resolves `actor`'s scope on the subject's project and passes it to `decide`,
  for a policy handed an actor rather than a `%Scope{}`. Bodyguard's contract
  is boolean, so a missing or scheduled project is `false`. Only callers going
  through `permit/4` with a `%Scope{}` are told about the deletion.
  """
  @spec for_actor(
          Lightning.Scope.actor(),
          term(),
          (Lightning.Scope.t() -> term())
        ) :: term()
  def for_actor(actor, subject, decide) do
    case Lightning.Scope.fetch(actor, subject) do
      {:ok, scope} -> scope |> decide.() |> hide_scheduled()
      {:error, _reason} -> false
    end
  end

  defp hide_scheduled({:error, :scheduled_for_deletion}), do: false
  defp hide_scheduled(answer), do: answer

  defp resolve_policy_module(policy) when is_atom(policy) do
    if Code.ensure_loaded?(policy) do
      policy
    else
      policy
      |> Atom.to_string()
      |> Macro.camelize()
      |> then(&Module.concat([Lightning.Policies, &1]))
    end
  end
end
