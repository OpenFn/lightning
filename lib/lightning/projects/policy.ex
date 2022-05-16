defmodule Lightning.Projects.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User

  # Super users can do anything
  def authorize(_action, %User{role: :superuser}, _params), do: true

  # Default blacklist
  def authorize(_action, _user, _params), do: false
end
