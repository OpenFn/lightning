defmodule LightningWeb.Channels.WorkflowJSON do
  @moduledoc """
  Renders workflow collaboration data structures for channels and LiveViews.
  """

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.ProjectCredential

  @doc """
  Renders credentials as a map with separate project and keychain credentials.
  """
  def render(credentials) do
    {project_credentials, keychain_credentials} =
      credentials
      |> Enum.split_with(fn
        %ProjectCredential{} -> true
        %KeychainCredential{} -> false
      end)

    %{
      project_credentials:
        project_credentials
        |> Enum.map(fn %ProjectCredential{
                         credential: credential,
                         id: project_credential_id
                       } ->
          %{
            id: credential.id,
            project_credential_id: project_credential_id,
            name: credential.name,
            external_id: credential.external_id,
            schema: credential.schema,
            owner: render_owner(credential.user),
            oauth_client_name: render_oauth_client_name(credential.oauth_client),
            inserted_at: credential.inserted_at,
            updated_at: credential.updated_at
          }
        end),
      keychain_credentials:
        keychain_credentials
        |> Enum.map(fn %KeychainCredential{} = keychain_credential ->
          %{
            id: keychain_credential.id,
            name: keychain_credential.name,
            path: keychain_credential.path,
            default_credential_id: keychain_credential.default_credential_id,
            inserted_at: keychain_credential.inserted_at,
            updated_at: keychain_credential.updated_at
          }
        end)
    }
  end

  defp render_owner(nil), do: nil

  defp render_owner(user) do
    %{
      id: user.id,
      name: "#{user.first_name} #{user.last_name}",
      email: user.email
    }
  end

  defp render_oauth_client_name(nil), do: nil
  defp render_oauth_client_name(%{name: name}), do: name
end
