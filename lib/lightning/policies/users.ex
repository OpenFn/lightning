defmodule Lightning.Policies.Users do
  @moduledoc """
  The Bodyguard Policy module for users roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User

  @type actions ::
          :access_admin_space
          | :access_own_credentials
          | :access_own_profile
          | :change_email
          | :change_password
          | :configure_external_auth_provider
          | :create_projects
          | :create_users
          | :delete_account
          | :delete_credential
          | :delete_users
          | :disable_users
          | :edit_projects
          | :edit_users
          | :view_credentials_audit_trail
          | :view_projects
          | :view_users

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
             :access_admin_space,
             :configure_external_auth_provider,
             :create_projects,
             :create_users,
             :delete_users,
             :disable_users,
             :edit_projects,
             :edit_users,
             :view_credentials_audit_trail,
             :view_projects,
             :view_users
           ] do
    role in [:superuser]
  end

  def authorize(action, %User{} = requesting_user, %User{} = authenticated_user)
      when action in [
             :access_own_credentials,
             :access_own_profile,
             :change_email,
             :change_password,
             :delete_account,
             :delete_credential,
             :edit_credentials,
             :view_credentials
           ] do
    requesting_user.id == authenticated_user.id
  end
end
