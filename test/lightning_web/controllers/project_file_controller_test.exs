defmodule LightningWeb.ProjectFileControllerTest do
  @moduledoc """
  `GET /project_files/:id/download` serves a project export archive.

  Two defects are covered here:

  1. `Policies.Exports.authorize/3` asks
     `Projects.member_of?(%Project{id: project_id}, user)` about a project it
     built from an id, so `scheduled_deletion` is never read. Scheduling
     deletion removes no membership rows, so an offboarded member still
     downloads the export during the grace window.

  2. `ProjectFileController` has no `action_fallback`, so a denial returns a
     bare `{:error, :forbidden}` from its `with` and never sends a response.
  """
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup do
    source = Path.join(System.tmp_dir!(), "project-file-#{Ecto.UUID.generate()}")
    File.write!(source, "the-export-archive")
    on_exit(fn -> File.rm(source) end)

    {:ok, path} =
      Lightning.Storage.store(source, "exports/#{Ecto.UUID.generate()}.zip")

    %{stored_path: path}
  end

  describe "GET /project_files/:id/download" do
    test "is refused for a member of a project scheduled for deletion", %{
      conn: conn,
      stored_path: stored_path
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :admin}],
          scheduled_deletion: DateTime.utc_now() |> DateTime.add(7, :day)
        )

      project_file =
        insert(:project_file,
          project: project,
          created_by: user,
          path: stored_path,
          status: :completed
        )

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/project_files/#{project_file.id}/download")

      assert conn.status == 403,
             "expected the export download to be refused on a shut-down project"

      refute conn.resp_body =~ "the-export-archive",
             "the export archive was served for a project scheduled for deletion"
    end

    test "renders a response when refused for a non-member", %{
      conn: conn,
      stored_path: stored_path
    } do
      project_file =
        insert(:project_file, path: stored_path, status: :completed)

      conn =
        conn
        |> log_in_user(insert(:user))
        |> get(~p"/project_files/#{project_file.id}/download")

      assert conn.status == 403,
             "expected a rendered 403; the controller has no action_fallback, " <>
               "so its `with` returns a bare {:error, :forbidden}"
    end

    test "serves the archive to a member of a live project", %{
      conn: conn,
      stored_path: stored_path
    } do
      user = insert(:user)
      project = insert(:project, project_users: [%{user_id: user.id}])

      project_file =
        insert(:project_file,
          project: project,
          created_by: user,
          path: stored_path,
          status: :completed
        )

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/project_files/#{project_file.id}/download")

      assert response(conn, 200) == "the-export-archive"
    end
  end
end
