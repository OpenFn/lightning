defmodule CredentialsServiceWeb.CredentialJSON do
  @moduledoc """
  JSON:API-style view for credentials. Per `docs/api.md`, the v1 contract
  standardizes on this envelope (the monolith's `ProjectJSON` shape) and the
  flat credentials shape is retired.

  Security invariant: `body` is NEVER serialized. Only environment NAMES are
  exposed.
  """
  alias CredentialsService.Credentials.Credential

  def index(%{credentials: credentials}) do
    %{data: Enum.map(credentials, &data/1), included: [], links: %{}}
  end

  def show(%{credential: credential}) do
    %{data: data(credential), included: [], links: %{}}
  end

  defp data(%Credential{} = credential) do
    %{
      type: "credentials",
      id: credential.id,
      attributes: %{
        name: credential.name,
        schema: credential.schema,
        external_id: credential.external_id,
        environments: environment_names(credential),
        transfer_status: credential.transfer_status,
        scheduled_deletion: credential.scheduled_deletion,
        inserted_at: credential.inserted_at,
        updated_at: credential.updated_at
      },
      relationships: %{
        owner: %{data: %{type: "users", id: credential.user_id}},
        projects: %{data: project_refs(credential)}
      }
    }

    # body intentionally excluded — never serialized.
  end

  defp environment_names(%Credential{credential_bodies: bodies}) when is_list(bodies) do
    Enum.map(bodies, & &1.name)
  end

  defp environment_names(_), do: []

  defp project_refs(%Credential{project_credentials: pcs}) when is_list(pcs) do
    Enum.map(pcs, &%{type: "projects", id: &1.project_id})
  end

  defp project_refs(_), do: []
end
