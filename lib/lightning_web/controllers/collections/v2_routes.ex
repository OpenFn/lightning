defmodule LightningWeb.Collections.V2Routes do
  @moduledoc """
  V2 collection routes: project-scoped (`/:project_id/:name`, `/:project_id/:name/:key`).
  """
  @behaviour LightningWeb.Plugs.VersionedRouter

  alias LightningWeb.CollectionsController, as: C

  @impl true
  def route(conn, "GET", [project_id, name]),
    do: C.stream(conn, %{"project_id" => project_id, "name" => name})

  def route(conn, "GET", [project_id, name, key]),
    do: C.get(conn, %{"project_id" => project_id, "name" => name, "key" => key})

  def route(conn, "PUT", [project_id, name, key]),
    do:
      C.put(
        conn,
        body_with(conn, %{
          "project_id" => project_id,
          "name" => name,
          "key" => key
        })
      )

  def route(conn, "POST", [project_id, name]),
    do:
      C.put_all(
        conn,
        body_with(conn, %{"project_id" => project_id, "name" => name})
      )

  def route(conn, "DELETE", [project_id, name, key]),
    do:
      C.delete(conn, %{
        "project_id" => project_id,
        "name" => name,
        "key" => key
      })

  def route(conn, "DELETE", [project_id, name]),
    do:
      C.delete_all(
        conn,
        all_params(conn, %{"project_id" => project_id, "name" => name})
      )

  def route(_conn, _method, _path), do: {:error, :not_found}

  defp body_with(conn, extra), do: Map.merge(conn.body_params, extra)

  defp all_params(conn, extra) do
    conn.query_params |> Map.merge(conn.body_params) |> Map.merge(extra)
  end
end
