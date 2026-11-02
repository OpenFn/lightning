defmodule LightningWeb.API.WorkflowHistory.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Workflows.Snapshot

  setup %{conn: conn} do
    viewer = insert(:user)
    project = insert(:project, project_users: [%{user: viewer, role: :viewer}])

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      viewer: viewer,
      project: project
    }
  end

  defp full_url(path), do: "#{LightningWeb.Endpoint.url()}#{path}"

  describe "listing snapshots" do
    test "a viewer on a session token gets the workflow's snapshots newest first, the current one marked latest",
         %{conn: conn, viewer: viewer, project: project} do
      workflow = insert(:simple_workflow, project: project, lock_version: 3)

      [first, second, current] =
        for version <- [1, 2, 3] do
          insert(:snapshot, workflow: workflow, lock_version: version)
        end

      page_one =
        full_url("/api/workflows/#{workflow.id}/snapshots?page=1&page_size=10")

      conn =
        conn
        |> session_conn(viewer)
        |> get(~p"/api/workflows/#{workflow.id}/snapshots")

      assert json_response(conn, 200) == %{
               "data" =>
                 for {snapshot, latest} <- [
                       {current, true},
                       {second, false},
                       {first, false}
                     ] do
                   %{
                     "id" => snapshot.id,
                     "lock_version" => snapshot.lock_version,
                     "inserted_at" => DateTime.to_iso8601(snapshot.inserted_at),
                     "latest" => latest
                   }
                 end,
               "links" => %{
                 "self" => page_one,
                 "first" => page_one,
                 "last" => page_one,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "pages the snapshots", %{conn: conn, viewer: viewer, project: project} do
      workflow = insert(:simple_workflow, project: project)

      [_first, second, _third] =
        for version <- [1, 2, 3] do
          insert(:snapshot, workflow: workflow, lock_version: version)
        end

      page = fn number ->
        full_url(
          "/api/workflows/#{workflow.id}/snapshots?page=#{number}&page_size=1"
        )
      end

      body =
        conn
        |> assign_bearer(viewer)
        |> get(~p"/api/workflows/#{workflow.id}/snapshots?page=2&page_size=1")
        |> json_response(200)

      assert Enum.map(body["data"], & &1["id"]) == [second.id]

      assert body["links"] == %{
               "self" => page.(2),
               "first" => page.(1),
               "last" => page.(3),
               "next" => page.(3),
               "prev" => page.(1)
             }
    end
  end

  describe "reading a snapshot" do
    test "a viewer on a session token gets the workflow as the snapshot kept it, with its lock_version",
         %{conn: conn, viewer: viewer, project: project} do
      workflow =
        insert(:simple_workflow,
          name: "as it was",
          project: project,
          positions: %{"a" => %{"x" => 1, "y" => 2}}
        )
        |> with_snapshot()

      [snapshot] = Snapshot.get_all_for(workflow)
      [job] = workflow.jobs
      [trigger] = workflow.triggers
      [edge] = workflow.edges

      Lightning.Repo.update!(Ecto.Changeset.change(workflow, name: "as it is"))

      conn =
        conn
        |> session_conn(viewer)
        |> get(~p"/api/workflows/#{workflow.id}/snapshots/#{snapshot.id}")

      assert json_response(conn, 200) == %{
               "snapshot" => %{
                 "id" => workflow.id,
                 "name" => "as it was",
                 "project_id" => project.id,
                 "lock_version" => snapshot.lock_version,
                 "positions" => %{"a" => %{"x" => 1, "y" => 2}},
                 "inserted_at" => DateTime.to_iso8601(snapshot.inserted_at),
                 "jobs" => [
                   %{
                     "id" => job.id,
                     "name" => job.name,
                     "body" => job.body,
                     "adaptor" => job.adaptor,
                     "project_credential_id" => nil,
                     "keychain_credential_id" => nil
                   }
                 ],
                 "triggers" => [
                   %{
                     "id" => trigger.id,
                     "type" => "webhook",
                     "enabled" => true,
                     "cron_expression" => nil,
                     "cron_cursor_job_id" => nil,
                     "custom_path" => nil,
                     "comment" => nil,
                     "webhook_reply" => "before_start",
                     "webhook_response_config" => nil
                   }
                 ],
                 "edges" => [
                   %{
                     "id" => edge.id,
                     "source_trigger_id" => trigger.id,
                     "source_job_id" => nil,
                     "target_job_id" => job.id,
                     "condition_type" => to_string(edge.condition_type),
                     "condition_expression" => nil,
                     "condition_label" => nil,
                     "enabled" => true
                   }
                 ]
               }
             }
    end
  end

  describe "listing versions" do
    test "a viewer on a session token gets the workflow's versions newest first",
         %{conn: conn, viewer: viewer, project: project} do
      workflow = insert(:simple_workflow, project: project)

      [older, newer] =
        for {source, offset} <- [{"app", -60}, {"cli", 0}] do
          insert(:workflow_version,
            workflow: workflow,
            source: source,
            inserted_at: DateTime.add(DateTime.utc_now(), offset)
          )
        end

      page_one =
        full_url("/api/workflows/#{workflow.id}/versions?page=1&page_size=10")

      conn =
        conn
        |> session_conn(viewer)
        |> get(~p"/api/workflows/#{workflow.id}/versions")

      assert json_response(conn, 200) == %{
               "data" =>
                 for version <- [newer, older] do
                   %{
                     "hash" => version.hash,
                     "source" => version.source,
                     "inserted_at" => DateTime.to_iso8601(version.inserted_at)
                   }
                 end,
               "links" => %{
                 "self" => page_one,
                 "first" => page_one,
                 "last" => page_one,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "pages the versions", %{conn: conn, viewer: viewer, project: project} do
      workflow = insert(:simple_workflow, project: project)

      [_oldest, middle, _newest] =
        for offset <- [-120, -60, 0] do
          insert(:workflow_version,
            workflow: workflow,
            inserted_at: DateTime.add(DateTime.utc_now(), offset)
          )
        end

      body =
        conn
        |> assign_bearer(viewer)
        |> get(~p"/api/workflows/#{workflow.id}/versions?page=2&page_size=1")
        |> json_response(200)

      assert Enum.map(body["data"], & &1["hash"]) == [middle.hash]

      assert body["links"]["next"] ==
               full_url(
                 "/api/workflows/#{workflow.id}/versions?page=3&page_size=1"
               )
    end
  end
end
