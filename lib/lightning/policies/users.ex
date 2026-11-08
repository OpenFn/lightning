defmodule Lightning.Policies.Users do
  @moduledoc """
  The Bodyguard Policy module for users roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Credentials.OauthClient
  alias Lightning.Policies.Decision
  alias Lightning.Scope

  @type actions ::
          :access_admin_space
          | :edit_credential
          | :delete_credential
          | :delete_account
          | :read_users
          | :write_users
          | :read_own_account
          | :update_own_account
          | :update_own_sign_in

  @spec authorize(actions(), User.t() | Scope.t(), any()) :: Decision.answer()

  # `operator?` is a fact about the caller alone, so the check made before any
  # target decides it.
  def authorize(action, %Scope{} = scope, _subject)
      when action in [:read_users, :write_users],
      do: Decision.instance(scope, nil, grant(action), Scope.operator?(scope))

  # A person reads their own account on either of their tokens. The service
  # account isn't a user, so it has no account to read.
  def authorize(:read_own_account, %Scope{} = scope, _subject),
    do: Decision.person(scope, true)

  # And changes their own names and contact preference on either token.
  # Nothing they may change this way is a way into the account, so it needs no
  # step-up. Which account the request names is the controller's to check.
  def authorize(:update_own_account, %Scope{} = scope, _subject),
    do: Decision.person(scope, true)

  # Their email and password are how they sign in, so changing either needs a
  # person at the keyboard who has just proved who they are: a session token,
  # stepped up.
  def authorize(:update_own_sign_in, %Scope{} = scope, _subject),
    do: Decision.session(scope, true, step_up: true)

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
    case Accounts.get_user_by_api_token(token) do
      %User{id: owner_id} -> authenticated_user.id == owner_id
      nil -> false
    end
  end

  def authorize(action, %User{} = authenticated_user, %OauthClient{} = client)
      when action in [:edit_credential, :delete_credential] do
    authenticated_user.id == client.user_id
  end

  defp grant(:read_users), do: "users:read"
  defp grant(:write_users), do: "users:write"
end
