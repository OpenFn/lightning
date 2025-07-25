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
  can_create = Permissions.can?(:credentials, :create_keychain_credential, project_user)
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
