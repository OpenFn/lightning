defmodule Lightning.Auditing.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User

  # Superusers can access the global audit page
  def authorize(_action, %User{role: :superuser}, _params), do: true

  # Default deny
  def authorize(_, _user, _project), do: false
end
