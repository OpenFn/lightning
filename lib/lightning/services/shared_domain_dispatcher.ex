defmodule Lightning.Services.SharedDomainDispatcher do
  @moduledoc """
  Adapter to call the extension when a project is initialized for new user.
  """
  @behaviour Lightning.Extensions.SharedDomain

  import Lightning.Services.AdapterHelper

  @impl true
  def register_user(attrs) do
    adapter().register_user(attrs)
  end

  @impl true
  def register_superuser(attrs) do
    adapter().register_superuser(attrs)
  end

  @impl true
  def create_user(attrs) do
    adapter().create_user(attrs)
  end

  @impl true
  def create_project(attrs) do
    adapter().create_project(attrs)
  end

  defp adapter, do: adapter(:shared_domain)
end
