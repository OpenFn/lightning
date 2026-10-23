defmodule LightningWeb.ApiCredentialsHelpers do
  @moduledoc false
  use Phoenix.VerifiedRoutes,
    endpoint: LightningWeb.Endpoint,
    router: LightningWeb.Router

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  import LightningWeb.ConnHelpers
  import Lightning.Factories
  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Repo

  @endpoint LightningWeb.Endpoint
  @secret "s3cr3t-never-rendered"

  def secret, do: @secret

  def put_credential(conn, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/credentials/#{id}", Jason.encode!(body))
  end

  def with_pat(conn, user) do
    assign_bearer(conn, Lightning.Accounts.generate_api_token(user))
  end

  def credential_body(attrs) do
    Map.merge(
      %{
        "name" => "Acme DHIS2",
        "schema" => "raw",
        "credential_bodies" => [
          %{"name" => "main", "body" => %{"password" => @secret}}
        ]
      },
      attrs
    )
  end

  def links(project_ids),
    do: Enum.map(project_ids, &%{"project_id" => &1})

  def main_body(credential_id),
    do: Credentials.get_credential_body(credential_id, "main").body

  def linked_project_ids(response) do
    response["credential"]["project_credentials"]
    |> Enum.map(& &1["project_id"])
    |> Enum.sort()
  end

  # A credential with a staging body beside its main one, linked to `project`.
  # Inserted directly, so the owner needn't have access to `project`.
  def existing_credential(owner, project) do
    insert(:credential,
      name: "Acme DHIS2",
      schema: "raw",
      user: owner,
      project_credentials: [%{project_id: project.id}]
    )
    |> with_body(%{name: "main", body: %{"password" => "old"}})
    |> with_body(%{name: "staging", body: %{"password" => "staging"}})
  end

  def scheduled_for_deletion(credential) do
    credential
    |> Ecto.Changeset.change(
      scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  def audit_ids(credential_id) do
    Repo.all(
      from a in Lightning.Credentials.Audit.base_query(),
        where: a.item_id == ^credential_id,
        select: a.id
    )
  end
end
