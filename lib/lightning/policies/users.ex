defmodule Lightning.Policies.Users do
  @moduledoc """
  The Bodyguard Policy module for users roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient

  @type actions ::
          :access_admin_space
          | :edit_credential
          | :delete_credential
          | :delete_account

  @spec authorize(actions(), Lightning.Accounts.User.t(), any()) :: boolean
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

  def authorize(:delete_api_token, %User{} = authenticated_user, token)
      when is_binary(token) do
    authenticated_user.id == Accounts.get_user_by_api_token(token).id
  end

  def authorize(action, %User{} = authenticated_user, %module{} = credential)
      when module in [Credential, OauthClient] and
             action in [:edit_credential, :delete_credential] do
    authenticated_user.id == credential.user_id
  end
end
