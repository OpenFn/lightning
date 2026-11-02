defmodule LightningWeb.ApiProjectMembersHelpers do
  @moduledoc """
  Requests and expected bodies for the project member routes.
  """
  use LightningWeb, :verified_routes

  import Ecto.Query
  import Phoenix.ConnTest, only: [dispatch: 5]
  import Plug.Conn, only: [put_req_header: 3]

  @endpoint LightningWeb.Endpoint

  @doc "Sends `body`, a map encoded as JSON or a raw string, with `verb`."
  def send_json(conn, verb, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, verb, path, encode(body))
  end

  defp encode(body) when is_binary(body), do: body
  defp encode(body), do: Jason.encode!(body)

  @doc "The member path for `user_id` in `project_id`."
  def member_path(project_id, user_id),
    do: ~p"/api/projects/#{project_id}/members/#{user_id}"

  @doc """
  One member as the routes show it: `user`'s fields, with `role` and the
  notification preferences given.
  """
  def member_json(project_id, user, role, opts \\ []) do
    %{
      "type" => "project_members",
      "id" => user.id,
      "attributes" => %{
        "email" => user.email,
        "first_name" => user.first_name,
        "last_name" => user.last_name,
        "role" => to_string(role),
        "failure_alert" => Keyword.get(opts, :failure_alert, false),
        "digest" => to_string(Keyword.get(opts, :digest, :never))
      },
      "relationships" => %{},
      "links" => %{
        "self" => LightningWeb.Endpoint.url() <> member_path(project_id, user.id)
      }
    }
  end

  @doc "The project's audit events, as `{event, actor_id}`, oldest first."
  def audit_events(project_id) do
    from(a in Lightning.Auditing.Audit,
      where: a.item_id == ^project_id,
      select: {a.event, a.actor_id},
      order_by: [a.inserted_at, a.event]
    )
    |> Lightning.Repo.all()
  end

  @doc "The role of `user_id` in `project_id`, or `nil`."
  def role_of(project_id, user_id) do
    from(pu in Lightning.Projects.ProjectUser,
      where: pu.project_id == ^project_id and pu.user_id == ^user_id,
      select: pu.role
    )
    |> Lightning.Repo.one()
  end
end
