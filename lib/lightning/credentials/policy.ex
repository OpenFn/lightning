defmodule Lightning.Credentials.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  def authorize(action, user, credential) when action in ~w[show]a,
    do: credential.user_id == user.id
end
