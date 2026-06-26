defmodule CredentialsService.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CredentialsService.Repo,
      CredentialsService.Vault,
      CredentialsServiceWeb.Endpoint
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: CredentialsService.Supervisor
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    CredentialsServiceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
