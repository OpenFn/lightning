defmodule LightningWeb.API.HistoryExports.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  setup %{conn: conn} do
    context = history_callers(conn)
    project = context.project
    author = insert(:user, first_name: "Ada", last_name: "Lovelace")

    completed =
      insert(:project_file,
        project: project,
        created_by: author,
        status: :completed,
        path: stored_zip(),
        inserted_at: ~U[2026-01-02 00:00:00Z],
        updated_at: ~U[2026-01-02 00:05:00Z]
      )

    enqueued =
      insert(:project_file,
        project: project,
        created_by: author,
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      )

    Map.merge(context, %{
      author: author,
      completed: completed,
      enqueued: enqueued
    })
  end

  describe "reading" do
    test "a viewer's session token lists the project's exports, newest first, a page at a time",
         %{project: project, author: author, completed: completed} do
      viewer = insert(:user)
      insert(:project_user, project: project, user: viewer, role: :viewer)

      base =
        "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/history_exports"

      conn =
        build_conn()
        |> session_conn(viewer)
        |> get(~p"/api/projects/#{project.id}/history_exports?page_size=1")

      assert json_response(conn, 200) == %{
               "data" => [
                 %{
                   "type" => "history_exports",
                   "id" => completed.id,
                   "attributes" => %{
                     "state" => "completed",
                     "filename" => Path.basename(completed.path),
                     "created_by_id" => author.id,
                     "created_by_name" => "Ada Lovelace",
                     "download_url" => "#{base}/#{completed.id}/download",
                     "inserted_at" => "2026-01-02T00:00:00Z",
                     "updated_at" => "2026-01-02T00:05:00Z"
                   },
                   "relationships" => %{},
                   "links" => %{"self" => "#{base}/#{completed.id}"}
                 }
               ],
               "included" => [],
               "links" => %{
                 "self" => "#{base}?page=1&page_size=1",
                 "first" => "#{base}?page=1&page_size=1",
                 "last" => "#{base}?page=2&page_size=1",
                 "next" => "#{base}?page=2&page_size=1",
                 "prev" => nil
               }
             }
    end

    test "a personal access token reads one export, with no filename or download until it is completed",
         %{viewer: viewer, project: project, enqueued: enqueued, author: author} do
      url =
        "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/history_exports/#{enqueued.id}"

      conn =
        get(
          viewer,
          ~p"/api/projects/#{project.id}/history_exports/#{enqueued.id}"
        )

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "history_exports",
                 "id" => enqueued.id,
                 "attributes" => %{
                   "state" => "enqueued",
                   "filename" => nil,
                   "created_by_id" => author.id,
                   "created_by_name" => "Ada Lovelace",
                   "download_url" => nil,
                   "inserted_at" => "2026-01-01T00:00:00Z",
                   "updated_at" => "2026-01-01T00:00:00Z"
                 },
                 "relationships" => %{},
                 "links" => %{"self" => url}
               },
               "included" => [],
               "links" => %{"self" => url}
             }
    end
  end

  describe "downloading" do
    test "a completed export's download_url serves its zip", %{
      viewer: viewer,
      project: project,
      completed: completed
    } do
      conn =
        get(
          viewer,
          ~p"/api/projects/#{project.id}/history_exports/#{completed.id}/download"
        )

      assert response(conn, 200) == "the-export-archive"

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ Path.basename(completed.path)
    end

    test "an export that isn't completed has nothing to download, 404 not_found",
         %{viewer: viewer, project: project, enqueued: enqueued} do
      viewer
      |> get(
        ~p"/api/projects/#{project.id}/history_exports/#{enqueued.id}/download"
      )
      |> assert_problem(404, :not_found, [])
    end
  end

  defp stored_zip do
    source = Path.join(System.tmp_dir!(), "export-#{Ecto.UUID.generate()}")
    File.write!(source, "the-export-archive")
    on_exit(fn -> File.rm(source) end)

    {:ok, path} =
      Lightning.Storage.store(source, "exports/#{Ecto.UUID.generate()}.zip")

    path
  end
end
