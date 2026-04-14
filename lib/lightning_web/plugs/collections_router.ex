defmodule LightningWeb.Plugs.CollectionsRouter do
  @moduledoc """
  Versioned routing plug for the Collections API.

  Mounted via `forward` in the Phoenix router, this plug resolves the
  API version from the `x-api-version` header and dispatches to the
  appropriate controller action based on version, HTTP method, and path
  segments.

  ## Version resolution

  The version is read from the `x-api-version` request header:

    * Missing or `"1"` -> v1
    * `"2"` -> v2
    * Any other value or multiple headers -> 400 Bad Request

  ## Routes

    * **V1** (name-scoped): `/:name`, `/:name/:key`
    * **V2** (project-scoped): `/:project_id/:name`, `/:project_id/:name/:key`

  Controller actions may return a `%Plug.Conn{}` (rendered directly) or
  an error tuple like `{:error, :not_found}`, which is passed to the
  fallback controller.
  """
  use Phoenix.Controller
  import Plug.Conn

  alias LightningWeb.CollectionsController, as: C
  alias LightningWeb.FallbackController

  @supported_versions ~w(1 2)

  def init(opts), do: opts

  def call(conn, _opts) do
    case resolve_version(conn) do
      {:ok, conn} ->
        case route(conn, conn.assigns.api_version, conn.method, conn.path_info) do
          %Plug.Conn{} = conn -> conn
          error -> FallbackController.call(conn, error)
        end

      {:error, conn} ->
        conn
    end
  end

  # -- Version resolution --------------------------------------------------

  defp resolve_version(conn) do
    case get_req_header(conn, "x-api-version") do
      [] -> {:ok, assign(conn, :api_version, :v1)}
      ["1"] -> {:ok, assign(conn, :api_version, :v1)}
      ["2"] -> {:ok, assign(conn, :api_version, :v2)}
      [value] -> {:error, reject_version(conn, value)}
      _many -> {:error, reject_version(conn, "multiple")}
    end
  end

  defp reject_version(conn, value) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error:
        "Unsupported API version: #{inspect(value)}. " <>
          "Supported versions: #{Enum.join(@supported_versions, ", ")}."
    })
    |> halt()
  end

  # -- V1: name-scoped -----------------------------------------------------

  defp route(conn, :v1, "GET", [name]),
    do: C.stream(conn, %{"name" => name})

  defp route(conn, :v1, "GET", [name, key]),
    do: C.get(conn, %{"name" => name, "key" => key})

  defp route(conn, :v1, "PUT", [name, key]),
    do: C.put(conn, body_with(conn, %{"name" => name, "key" => key}))

  defp route(conn, :v1, "POST", [name]),
    do: C.put_all(conn, body_with(conn, %{"name" => name}))

  defp route(conn, :v1, "DELETE", [name, key]),
    do: C.delete(conn, %{"name" => name, "key" => key})

  defp route(conn, :v1, "DELETE", [name]),
    do: C.delete_all(conn, all_params(conn, %{"name" => name}))

  # -- V2: project-scoped --------------------------------------------------

  defp route(conn, :v2, "GET", [project_id, name]),
    do: C.stream(conn, %{"project_id" => project_id, "name" => name})

  defp route(conn, :v2, "GET", [project_id, name, key]),
    do:
      C.get(conn, %{
        "project_id" => project_id,
        "name" => name,
        "key" => key
      })

  defp route(conn, :v2, "PUT", [project_id, name, key]),
    do:
      C.put(
        conn,
        body_with(conn, %{
          "project_id" => project_id,
          "name" => name,
          "key" => key
        })
      )

  defp route(conn, :v2, "POST", [project_id, name]),
    do:
      C.put_all(
        conn,
        body_with(conn, %{"project_id" => project_id, "name" => name})
      )

  defp route(conn, :v2, "DELETE", [project_id, name, key]),
    do:
      C.delete(conn, %{
        "project_id" => project_id,
        "name" => name,
        "key" => key
      })

  defp route(conn, :v2, "DELETE", [project_id, name]),
    do:
      C.delete_all(
        conn,
        all_params(conn, %{"project_id" => project_id, "name" => name})
      )

  # -- Fallback -------------------------------------------------------------

  defp route(conn, _version, _method, _path) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not Found"}))
  end

  # -- Helpers --------------------------------------------------------------

  defp body_with(conn, extra), do: Map.merge(conn.body_params, extra)

  defp all_params(conn, extra) do
    conn.query_params |> Map.merge(conn.body_params) |> Map.merge(extra)
  end
end
