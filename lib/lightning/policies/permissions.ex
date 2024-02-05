defmodule Lightning.Policies.Permissions do
  @moduledoc """
  This module defines a unique interface managing authorizations in Lightning.

  Users in Lightning have instance-wide and project-wide roles which determine their level of access to resources in the application. Fo rmore details see the [documentation](https://docs.openfn.org/documentation/about-lightning#roles-and-permissions).

  These authorizations policies are all implemented under the `lib/lightning/policies` folder. In that folder you can find 3 files:
  - The `users.ex` file has all the policies for the instances wide access levels
  - The `project_users.ex` file has all the policies for the project wide access levels
  - The `permissions.ex` file defines the `Lightning.Policies.Permissions.can/4` interface. Which is a wrapper around the `Bodyguard.permit/4` function.
  We use that interface to be able to harmonize the use of policies accross the entire app.

  All the policies are tested in the `test/lightning/policies` folder. And the test are written in a way that allows the reader to quickly who can do what in the app.

  We have two variants of the `Lightning.Policies.Permissions.can/4` interface:
  - `Lightning.Policies.Permissions.can(policy, action, actor, resource)` returns `:ok` if the actor can perform the action on the resource and `{:error, :unauthorized}` otherwise.
  - `Lightning.Policies.Permissions.can?(policy, action, actor, resource)` returns `true` if the actor can perform the action on the resource and `false` otherwise.

  Here is an example of how we the `Lightning.Policies.Permissions.can/4` interface to check if the a user can edit a job or not
  ```elixir
  can_edit_workflow = Lightning.Policies.ProjectUsers |> Lightning.Policies.Permissions.can?(:edit_workflow, socket.assigns.current_user, socket.assigns.project)

  if can_edit_workflow do
    # allow user to edit the workflow
  else
    # quick user out
  end
  ```
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
    Bodyguard.permit(policy, action, user, params)
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
    case can(policy, action, user, params) do
      :ok -> true
      {:error, :unauthorized} -> false
    end
  end
end
