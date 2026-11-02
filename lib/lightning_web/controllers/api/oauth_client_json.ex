defmodule LightningWeb.API.OauthClientJSON do
  @moduledoc """
  JSON views for OAuth clients. `client_secret` is never rendered, and
  `project_ids` holds only the links the controller left in.
  """

  import LightningWeb.API.Helpers

  alias Lightning.Credentials.OauthClient

  @fields [
    :id,
    :name,
    :client_id,
    :authorization_endpoint,
    :token_endpoint,
    :revocation_endpoint,
    :userinfo_endpoint,
    :introspection_endpoint,
    :scopes_doc_url,
    :mandatory_scopes,
    :optional_scopes,
    :global,
    :user_id,
    :inserted_at,
    :updated_at
  ]

  def index(%{page: page, filters: filters, conn: conn}) do
    %{
      data: Enum.map(page.entries, &data/1),
      links: pagination_links(conn, page, filters)
    }
  end

  def show(%{oauth_client: client}), do: %{data: data(client)}

  defp data(%OauthClient{} = client) do
    client
    |> Map.take(@fields)
    |> Map.put(
      :project_ids,
      Enum.map(client.project_oauth_clients, & &1.project_id)
    )
  end
end
