defmodule LightningWeb.ApiSandboxesHelpers do
  @moduledoc false
  use LightningWeb, :verified_routes

  import Lightning.Factories
  import Phoenix.ConnTest, only: [dispatch: 5]
  import Plug.Conn, only: [put_req_header: 3]

  @endpoint LightningWeb.Endpoint

  @doc "Sends `body` as JSON with `verb` to `path`."
  def send_json(conn, verb, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, verb, path, Jason.encode!(body))
  end

  def put_sandbox(conn, project_id, id, body),
    do:
      send_json(
        conn,
        :put,
        ~p"/api/projects/#{project_id}/sandboxes/#{id}",
        body
      )

  def preview_merge(conn, project_id, id, body \\ %{}),
    do:
      send_json(
        conn,
        :post,
        ~p"/api/projects/#{project_id}/sandboxes/#{id}/merge_previews",
        body
      )

  def merge_sandbox(conn, project_id, id, body \\ %{}),
    do:
      send_json(
        conn,
        :post,
        ~p"/api/projects/#{project_id}/sandboxes/#{id}/merges",
        body
      )

  @doc """
  A project with an owner, and a sandbox of it whose owner is `sandbox_owner`
  and where the parent's owner is an admin, as provisioning leaves them.
  """
  def project_with_sandbox(owner, sandbox_owner, attrs \\ []) do
    parent = insert(:project, project_users: [%{user: owner, role: :owner}])

    sandbox =
      insert(
        :project,
        Keyword.merge(
          [
            parent: parent,
            name: "staging",
            project_users: [
              %{user: sandbox_owner, role: :owner},
              %{user: owner, role: :admin}
            ]
          ],
          attrs
        )
      )

    {parent, sandbox}
  end
end
