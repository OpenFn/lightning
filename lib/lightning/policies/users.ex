defmodule Lightning.Policies.Users do
  @moduledoc """
  The Bodyguard Policy module for users roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User

  @type actions ::
          :create_projects
          | :view_projects
          | :edit_projects
          | :create_projects
          | :view_users
          | :edit_users
          | :delete_users
          | :disable_users
          | :configure_external_auth_provider
          | :view_credentials_audit_trail
          | :change_password
          | :delete_account
          | :view_credentials
          | :edit_credentials
          | :delete_credential

  @doc """
  authorize/3 takes an action, a user, and a project. It checks the user's role
  for this project and returns `true` if the user can perform the action and
  false if they cannot.

  Note that permissions are grouped by action.

  We deny by default, so if a user's role is not added to the allow roles list
  for a particular action they are denied.
  """
  @spec authorize(actions(), Lightning.Accounts.User.t(), any) :: boolean
  def authorize(action, %User{role: role}, _project)
      when action in [
             :view_projects,
             :edit_projects,
             :create_projects,
             :view_users,
             :edit_users,
             :delete_users,
             :disable_users,
             :configure_external_auth_provider,
             :view_credentials_audit_trail
           ] do
    role in [:superuser]
  end

  def authorize(action, %User{} = requesting_user, %User{} = authenticated_user)
      when action in [
             :change_password,
             :delete_account,
             :view_credentials,
             :edit_credentials,
             :delete_credential
           ] do
    requesting_user.id == authenticated_user.id
  end
end
