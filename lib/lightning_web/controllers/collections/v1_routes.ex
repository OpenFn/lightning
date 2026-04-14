defmodule LightningWeb.Collections.V1Routes do
  @moduledoc """
  V1 collection routes: name-scoped (`/:name`, `/:name/:key`).
  """
  @behaviour LightningWeb.Plugs.VersionedRouter

  alias LightningWeb.CollectionsController, as: C

  @impl true
  def route(conn, "GET", [name]),
    do: C.stream(conn, %{"name" => name})

  def route(conn, "GET", [name, key]),
    do: C.get(conn, %{"name" => name, "key" => key})

  def route(conn, "PUT", [name, key]),
    do: C.put(conn, body_with(conn, %{"name" => name, "key" => key}))

  def route(conn, "POST", [name]),
    do: C.put_all(conn, body_with(conn, %{"name" => name}))

  def route(conn, "DELETE", [name, key]),
    do: C.delete(conn, %{"name" => name, "key" => key})

  def route(conn, "DELETE", [name]),
    do: C.delete_all(conn, all_params(conn, %{"name" => name}))

  def route(_conn, _method, _path), do: {:error, :not_found}

  defp body_with(conn, extra), do: Map.merge(conn.body_params, extra)

  defp all_params(conn, extra) do
    conn.query_params |> Map.merge(conn.body_params) |> Map.merge(extra)
  end
end
