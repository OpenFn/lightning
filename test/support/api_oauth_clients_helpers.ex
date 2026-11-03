defmodule LightningWeb.ApiOauthClientsHelpers do
  @moduledoc """
  Builders shared by the OAuth clients API tests.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: LightningWeb.Endpoint,
    router: LightningWeb.Router

  import Phoenix.ConnTest, only: [dispatch: 5]
  import Plug.Conn, only: [put_req_header: 3]

  alias Lightning.Credentials.OauthClient
  alias Lightning.Repo

  @endpoint LightningWeb.Endpoint

  @doc "The JSON a client renders as, with `project_ids` given."
  def client_json(%OauthClient{} = client, project_ids) do
    %{
      "id" => client.id,
      "name" => client.name,
      "client_id" => client.client_id,
      "authorization_endpoint" => client.authorization_endpoint,
      "token_endpoint" => client.token_endpoint,
      "revocation_endpoint" => client.revocation_endpoint,
      "userinfo_endpoint" => client.userinfo_endpoint,
      "introspection_endpoint" => client.introspection_endpoint,
      "scopes_doc_url" => client.scopes_doc_url,
      "mandatory_scopes" => client.mandatory_scopes,
      "optional_scopes" => client.optional_scopes,
      "global" => client.global,
      "user_id" => client.user_id,
      "project_ids" => project_ids,
      "inserted_at" => DateTime.to_iso8601(client.inserted_at),
      "updated_at" => DateTime.to_iso8601(client.updated_at)
    }
  end

  @doc "A body every field of which a create accepts."
  def client_body(attrs \\ %{}) do
    Map.merge(
      %{
        "name" => "Google Sheets",
        "client_id" => "1234.apps.googleusercontent.com",
        "client_secret" => "s3cr3t-never-rendered",
        "authorization_endpoint" =>
          "https://accounts.google.com/o/oauth2/v2/auth",
        "token_endpoint" => "https://oauth2.googleapis.com/token",
        "mandatory_scopes" => "openid,email",
        "optional_scopes" => "https://www.googleapis.com/auth/spreadsheets"
      },
      attrs
    )
  end

  def put_client(conn, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(
      @endpoint,
      :put,
      ~p"/api/oauth_clients/#{id}",
      Jason.encode!(body)
    )
  end

  def delete_client(conn, id),
    do: dispatch(conn, @endpoint, :delete, ~p"/api/oauth_clients/#{id}", nil)

  def linked_project_ids(client_id) do
    OauthClient
    |> Repo.get!(client_id)
    |> Repo.preload(:project_oauth_clients)
    |> Map.fetch!(:project_oauth_clients)
    |> Enum.map(& &1.project_id)
    |> Enum.sort()
  end
end
