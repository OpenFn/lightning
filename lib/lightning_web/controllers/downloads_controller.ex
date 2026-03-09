defmodule LightningWeb.DownloadsController do
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  action_fallback(LightningWeb.FallbackController)

  @batch_size 500

  def download_project_yaml(conn, %{"id" => id}) do
    with %Projects.Project{} = project <-
           Lightning.Projects.get_project(id) || {:error, :not_found},
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_user,
             project
           ) do
      {:ok, yaml} = Projects.export_project(:yaml, id)

      conn
      |> put_resp_content_type("text/yaml")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"project-#{id}.yaml\""
      )
      |> put_root_layout(false)
      |> put_flash(:info, "Project yaml exported successfully")
      |> send_resp(200, yaml)
    end
  end

  def download_collection_json(conn, %{
        "project_id" => project_id,
        "name" => name
      }) do
    with %Projects.Project{} = project <-
           Projects.get_project(project_id) || {:error, :not_found},
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_user,
             project
           ),
         {:ok, collection} <- Collections.get_collection(name),
         true <- collection.project_id == project.id || {:error, :not_found} do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"#{name}.json\""
      )
      |> stream_collection_items(collection)
    end
  end

  defp stream_collection_items(conn, collection) do
    conn = send_chunked(conn, 200)

    items_stream =
      Stream.unfold(nil, fn cursor ->
        case Collections.get_all(
               collection,
               %{cursor: cursor, limit: @batch_size},
               nil
             ) do
          [] -> nil
          items -> {items, List.last(items).id}
        end
      end)
      |> Stream.flat_map(& &1)

    {:ok, conn} = Plug.Conn.chunk(conn, "[")

    {conn, _first?} =
      Enum.reduce_while(items_stream, {conn, true}, fn item, {conn, first?} ->
        prefix = if first?, do: "", else: ","
        encoded = prefix <> Jason.encode!(item)

        case Plug.Conn.chunk(conn, encoded) do
          {:ok, conn} -> {:cont, {conn, false}}
          {:error, :closed} -> {:halt, {conn, false}}
        end
      end)

    {:ok, conn} = Plug.Conn.chunk(conn, "]")

    conn
  end
end
