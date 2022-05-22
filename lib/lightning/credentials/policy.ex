defmodule Lightning.Credentials.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Credentials

  def authorize(_action, %User{role: :superuser}, _params), do: true

  def authorize(
        action,
        %User{role: :user} = user,
        %{"credential_id" => credential_id} = _params
      )
      when action in ~w[show]a do
    !!Credentials.get_credential_for_user(
      credential_id,
      user.id
    )
  end

  def authorize(_action, _user, _params), do: false
end
