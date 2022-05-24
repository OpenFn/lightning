defmodule Lightning.Credentials.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Credentials

  def authorize(
        action,
        %{"user_id" => user_id} = _user,
        %{"credential_id" => credential_id} = _params
      )
      when action in ~w[show]a do
    !!Credentials.get_credential_for_user(
      credential_id,
      user_id
    )
  end
end
