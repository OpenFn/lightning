defmodule Lightning.Policies.Users do
  @moduledoc """
  The Bodyguard Policy module for users roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential

  @type actions ::
          :access_admin_space
          | :edit_credential
          | :delete_credential
          | :delete_account

  @doc """
  authorize/3 takes an action, a user, and a project. It checks the user's role
  for this project and returns `true` if the user can perform the action and
  false if they cannot.

  Note that permissions are grouped by action.

  We deny by default, so if a user's role is not added to the allow roles list
  for a particular action they are denied.
  """
  @spec authorize(actions(), Lightning.Accounts.User.t(), any) :: boolean
  def authorize(:access_admin_space, %User{role: role}, _params) do
    role in [:superuser]
  end

  # You can only delete an account if the id in the URL is matching your id
  def authorize(
        :delete_account,
        %User{} = authenticated_user,
        %User{} = account_user
      ) do
    authenticated_user.id == account_user.id
  end

  def authorize(
        :delete_api_token,
        %User{} = authenticated_user,
        token
      ) do
    authenticated_user.id == Accounts.get_user_by_api_token(token).id
  end

  def authorize(action, %User{} = authenticated_user, %Credential{} = credential)
      when action in [:edit_credential, :delete_credential] do
    authenticated_user.id == credential.user_id
  end
end
