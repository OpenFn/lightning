defmodule LightningWeb.API.CredentialEnvironmentJSON do
  @moduledoc """
  JSON views for a credential's environments. Only the name and timestamps are
  rendered; a body never is.
  """

  def index(%{environments: environments}),
    do: %{data: Enum.map(environments, &environment/1)}

  def show(%{environment: environment}), do: %{data: environment(environment)}

  defp environment(environment) do
    %{
      name: environment.name,
      inserted_at: environment.inserted_at,
      updated_at: environment.updated_at
    }
  end
end
