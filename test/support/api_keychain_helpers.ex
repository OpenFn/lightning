defmodule LightningWeb.ApiKeychainHelpers do
  @moduledoc """
  Builders shared by the keychain credentials API tests.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: LightningWeb.Endpoint,
    router: LightningWeb.Router

  import Phoenix.ConnTest, only: [dispatch: 5]
  import Plug.Conn, only: [put_req_header: 3]

  @endpoint LightningWeb.Endpoint

  @doc "The JSON a keychain credential, with its associations loaded, renders as."
  def keychain_json(keychain) do
    %{
      "id" => keychain.id,
      "project_id" => keychain.project_id,
      "name" => keychain.name,
      "path" => keychain.path,
      "default_credential_id" => keychain.default_credential_id,
      "default_credential_name" =>
        keychain.default_credential && keychain.default_credential.name,
      "created_by" => %{
        "id" => keychain.created_by.id,
        "email" => keychain.created_by.email
      },
      "inserted_at" => DateTime.to_iso8601(keychain.inserted_at),
      "updated_at" => DateTime.to_iso8601(keychain.updated_at)
    }
  end

  def put_keychain(conn, project_id, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(
      @endpoint,
      :put,
      ~p"/api/projects/#{project_id}/keychain_credentials/#{id}",
      Jason.encode!(body)
    )
  end

  def delete_keychain(conn, project_id, id) do
    dispatch(
      conn,
      @endpoint,
      :delete,
      ~p"/api/projects/#{project_id}/keychain_credentials/#{id}",
      nil
    )
  end
end
