defmodule LightningWeb.API.CredentialJSON do
  @moduledoc """
  JSON views for the API credential endpoints
  """

  alias Lightning.Credentials.Credential
  alias Lightning.Projects.ProjectCredential

  def create(%{credential: credential}) do
    %{
      credential: credential_data(credential),
      errors: %{}
    }
  end

  defp credential_data(%Credential{} = credential) do
    %{
      id: credential.id,
      name: credential.name,
      schema: credential.schema,
      production: credential.production,
      external_id: credential.external_id,
      user_id: credential.user_id,
      project_credentials: render_project_credentials(credential.project_credentials),
      projects: render_projects(credential.projects),
      inserted_at: credential.inserted_at,
      updated_at: credential.updated_at
    }
    # Note: body field is intentionally excluded for security reasons
  end

  defp render_project_credentials(project_credentials) when is_list(project_credentials) do
    Enum.map(project_credentials, &render_project_credential/1)
  end

  defp render_project_credentials(_), do: []

  defp render_project_credential(%ProjectCredential{} = pc) do
    %{
      id: pc.id,
      project_id: pc.project_id,
      credential_id: pc.credential_id,
      inserted_at: pc.inserted_at,
      updated_at: pc.updated_at
    }
  end

  defp render_projects(projects) when is_list(projects) do
    Enum.map(projects, &render_project/1)
  end

  defp render_projects(_), do: []

  defp render_project(project) do
    %{
      id: project.id,
      name: project.name,
      description: project.description
    }
  end
end
