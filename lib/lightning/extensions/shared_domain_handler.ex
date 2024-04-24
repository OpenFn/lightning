defmodule Lightning.Extensions.SharedDomainHandler do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.SharedDomain

  alias Lightning.Repo

  @impl true
  def register_user(user_params),
    do: Lightning.Accounts.register_user(Repo, user_params)

  @impl true
  def create_project(attrs),
    do: Lightning.Projects.create_project(Repo, attrs)
end
