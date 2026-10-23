defmodule LightningWeb.ApiProjectsHelpers do
  @moduledoc false
  use LightningWeb, :verified_routes

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.ConnHelpers, only: [assign_bearer: 2]
  import Phoenix.ConnTest, only: [put: 3]
  import Plug.Conn, only: [put_req_header: 3]

  @endpoint LightningWeb.Endpoint

  def put_project(conn, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/projects/#{id}", Jason.encode!(body))
  end

  def with_pat(conn, user) do
    assign_bearer(conn, Lightning.Accounts.generate_api_token(user))
  end

  def members_of(project_id) do
    from(pu in Lightning.Projects.ProjectUser,
      join: u in assoc(pu, :user),
      where: pu.project_id == ^project_id,
      select: {u.email, pu.role}
    )
    |> Lightning.Repo.all()
    |> Enum.sort()
  end

  def sorted_members(response) do
    response["data"]["attributes"]["members"]
    |> Enum.sort_by(& &1["email"])
  end

  def four_members do
    for role <- ~w(owner admin editor viewer) do
      %{"email" => insert(:user).email, "role" => role}
    end
  end

  def scheduled_project(project_users \\ []) do
    insert(:project,
      scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second),
      project_users: project_users
    )
  end
end
