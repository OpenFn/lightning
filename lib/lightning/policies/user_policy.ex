defmodule Lightning.Policies.UserPolicy do
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User

  def authorize(:create_projects, %User{role: :user}, _project), do: false

  def authorize(:create_projects, %User{role: role}, _project)
      when role in [:superuser, :admin],
      do: true
end
