defmodule LightningWeb.API.HistoryExports.ExportingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.Auditing.Audit
  alias Lightning.Projects.File, as: ProjectFile
  alias Lightning.Repo

  setup %{conn: conn} do
    context = history_callers(conn)

    Map.put(
      context,
      :path,
      ~p"/api/projects/#{context.project.id}/history_exports"
    )
  end

  describe "exporting" do
    test "a session token asks for an export of what a filter matches, and gets it back enqueued",
         %{path: path, editor_user: editor, project: project} do
      editor =
        Repo.update!(
          Ecto.Changeset.change(editor, first_name: "Ada", last_name: "Lovelace")
        )

      conn =
        build_conn()
        |> session_conn(editor)
        |> post(path, %{filter: %{state: "failed"}})

      assert %{"data" => %{"id" => id, "attributes" => attributes}} =
               body = json_response(conn, 202)

      export = Repo.get!(ProjectFile, id)

      url =
        "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/history_exports/#{id}"

      assert body == %{
               "data" => %{
                 "type" => "history_exports",
                 "id" => id,
                 "attributes" => %{
                   "state" => "enqueued",
                   "filename" => nil,
                   "created_by_id" => editor.id,
                   "created_by_name" => "Ada Lovelace",
                   "download_url" => nil,
                   "inserted_at" => attributes["inserted_at"],
                   "updated_at" => attributes["updated_at"]
                 },
                 "relationships" => %{},
                 "links" => %{"self" => url}
               },
               "included" => [],
               "links" => %{"self" => url}
             }

      assert {export.project_id, export.created_by_id, export.type} ==
               {project.id, editor.id, :export}

      assert %Audit{metadata: %{"search_params" => %{"status" => ["failed"]}}} =
               Repo.get_by!(Audit, item_id: project.id, event: "requested")
    end

    test "a personal access token asks for an export of everything when the body sends no filter",
         %{path: path, editor: editor} do
      conn = post(editor, path, %{})

      assert json_response(conn, 202)["data"]["attributes"]["filename"] == nil
      assert Repo.aggregate(ProjectFile, :count) == 1
    end
  end

  describe "refusals" do
    test "bad filters, work_order_ids or another key are 422 with every problem, and nothing is exported",
         %{path: path, editor: editor} do
      for {body, entries} <- [
            {%{filter: %{state: "sideways"}, work_order_ids: []},
             [
               entry("/filter/state", "not_allowed", "has an invalid entry"),
               entry("/work_order_ids", "unknown_key", "is not accepted")
             ]},
            {%{filter: []}, [entry("/filter", "type", "must be an object")]},
            {%{format: "csv"},
             [entry("/format", "unknown_key", "is not accepted")]}
          ] do
        editor
        |> post(path, body)
        |> assert_problem(422, :invalid, entries)
      end

      editor
      |> post(path, Jason.encode!(nil))
      |> assert_problem(400, :malformed, [])

      assert Repo.aggregate(ProjectFile, :count) == 0
    end
  end

  defp entry(pointer, code, detail),
    do: %{"pointer" => "#" <> pointer, "code" => code, "detail" => detail}

  describe "stale writes" do
    test "a project another request deletes mid-request answers 409 concurrent_edit, and nothing is exported",
         %{path: path, editor: editor, project: project} do
      Lightning.RaceHelpers.delete_project_mid_save(project.id)

      editor
      |> post(path, %{})
      |> assert_problem(409, :concurrent_edit, [])

      assert {Repo.reload(project), Repo.aggregate(ProjectFile, :count)} ==
               {nil, 0}
    end
  end
end
