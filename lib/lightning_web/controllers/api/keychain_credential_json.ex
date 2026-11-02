defmodule LightningWeb.API.KeychainCredentialJSON do
  @moduledoc """
  JSON views for a project's keychain credentials. Each names its default
  credential and the person who created it, by id and email.
  """

  import LightningWeb.API.Helpers

  alias Lightning.Credentials.KeychainCredential

  def index(%{page: page, filters: filters, conn: conn}) do
    %{
      data: Enum.map(page.entries, &data/1),
      links: pagination_links(conn, page, filters)
    }
  end

  def show(%{keychain_credential: keychain}), do: %{data: data(keychain)}

  defp data(%KeychainCredential{} = keychain) do
    %{
      id: keychain.id,
      project_id: keychain.project_id,
      name: keychain.name,
      path: keychain.path,
      default_credential_id: keychain.default_credential_id,
      default_credential_name:
        keychain.default_credential && keychain.default_credential.name,
      created_by: %{
        id: keychain.created_by.id,
        email: keychain.created_by.email
      },
      inserted_at: keychain.inserted_at,
      updated_at: keychain.updated_at
    }
  end
end
