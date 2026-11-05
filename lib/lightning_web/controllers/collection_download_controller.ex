defmodule LightningWeb.CollectionDownloadController do
  @moduledoc """
  Downloads a collection's items from the browser, as one JSON array. It
  answers errors as the other browser controllers do, not as the
  `/collections` API does.
  """
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Policies.Permissions

  action_fallback LightningWeb.BrowserFallbackController

  def download(conn, %{"project_id" => project_id, "name" => name}) do
    with {:ok, uuid} <- cast_uuid(project_id),
         {:ok, collection} <- Collections.get_collection(uuid, name),
         :ok <-
           Permissions.can(
             :collections,
             :access_collection,
             conn.assigns.current_user,
             collection
           ) do
      items_stream = Collections.stream_all(collection, %{})

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{name}.json")
      )
      |> stream_as_json_array(items_stream)
    end
  end

  defp cast_uuid(project_id) do
    case Ecto.UUID.cast(project_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :bad_request}
    end
  end

  defp stream_as_json_array(conn, items_stream) do
    conn = send_chunked(conn, 200)
    {:ok, conn} = Plug.Conn.chunk(conn, "[")

    {conn, _first?} =
      Enum.reduce_while(items_stream, {conn, true}, fn item, {conn, first?} ->
        prefix = if first?, do: "", else: ","

        case Plug.Conn.chunk(conn, prefix <> Jason.encode!(item)) do
          {:ok, conn} -> {:cont, {conn, false}}
          {:error, :closed} -> {:halt, {conn, false}}
        end
      end)

    {:ok, conn} = Plug.Conn.chunk(conn, "]")
    conn
  end
end
