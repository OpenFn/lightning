defmodule LightningWeb.API.ProvisioningTriggerExportTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "exporting triggers" do
    setup [:assign_bearer_for_api]

    test "returns a webhook trigger with webhook_reply in the response", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      trigger =
        build(:trigger,
          type: :webhook,
          webhook_reply: :after_completion
        )

      job = build(:job)

      %{triggers: [%{id: trigger_id}]} =
        build(:workflow, project: project)
        |> with_trigger(trigger)
        |> with_job(job)
        |> with_edge({trigger, job}, condition_type: :always)
        |> insert()

      conn = get(conn, ~p"/api/provision/#{project.id}")
      response = json_response(conn, 200)

      assert %{
               "workflows" => [
                 %{
                   "triggers" => [trigger_json]
                 }
               ]
             } = response["data"]

      assert %{
               "id" => ^trigger_id,
               "type" => "webhook",
               "enabled" => true,
               "webhook_reply" => "after_completion"
             } = trigger_json
    end

    test "returns a webhook trigger with webhook_response_config in the response",
         %{
           conn: conn,
           user: user
         } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      trigger =
        build(:trigger,
          type: :webhook,
          webhook_reply: :after_completion,
          webhook_response_config:
            build(:webhook_response_config,
              success_code: 200,
              error_code: 500
            )
        )

      job = build(:job)

      %{triggers: [%{id: trigger_id}]} =
        build(:workflow, project: project)
        |> with_trigger(trigger)
        |> with_job(job)
        |> with_edge({trigger, job}, condition_type: :always)
        |> insert()

      conn = get(conn, ~p"/api/provision/#{project.id}")
      response = json_response(conn, 200)

      assert %{
               "workflows" => [
                 %{
                   "triggers" => [trigger_json]
                 }
               ]
             } = response["data"]

      assert %{
               "id" => ^trigger_id,
               "type" => "webhook",
               "webhook_reply" => "after_completion",
               "webhook_response_config" => %{
                 "success_code" => 200,
                 "error_code" => 500
               }
             } = trigger_json
    end

    test "omits webhook_response_config when it is nil", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      trigger = build(:trigger, type: :webhook)
      job = build(:job)

      build(:workflow, project: project)
      |> with_trigger(trigger)
      |> with_job(job)
      |> with_edge({trigger, job}, condition_type: :always)
      |> insert()

      conn = get(conn, ~p"/api/provision/#{project.id}")
      response = json_response(conn, 200)

      assert %{
               "workflows" => [%{"triggers" => [trigger_json]}]
             } = response["data"]

      refute Map.has_key?(trigger_json, "webhook_response_config")
    end

    test "returns a cron trigger with cron_cursor_job_id in the response", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      %{triggers: [trigger], jobs: [%{id: job_id}]} =
        insert(:simple_workflow, project: project)

      trigger_id = trigger.id

      {:ok, _trigger} =
        trigger
        |> Ecto.Changeset.change(
          type: :cron,
          cron_expression: "0 * * * *",
          cron_cursor_job_id: job_id
        )
        |> Lightning.Repo.update()

      conn = get(conn, ~p"/api/provision/#{project.id}")
      response = json_response(conn, 200)

      assert %{
               "workflows" => [
                 %{
                   "triggers" => [trigger_json]
                 }
               ]
             } = response["data"]

      assert %{
               "id" => ^trigger_id,
               "type" => "cron",
               "cron_expression" => "0 * * * *",
               "cron_cursor_job_id" => ^job_id
             } = trigger_json
    end

    test "a custom path is exported only when the server would accept it", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      cases = [
        {"facility-001", {:ok, "facility-001"}},
        {"some/legacy/path", :error},
        {nil, :error}
      ]

      expected_by_trigger_id =
        for {path, expected} <- cases, into: %{} do
          trigger =
            insert(:trigger,
              type: :webhook,
              workflow: insert(:workflow, project: project),
              custom_path: nil
            )

          Lightning.Repo.update_all(
            from(t in Lightning.Workflows.Trigger, where: t.id == ^trigger.id),
            set: [custom_path: path]
          )

          {trigger.id, expected}
        end

      conn = get(conn, ~p"/api/provision/#{project.id}")

      exported =
        for %{"triggers" => triggers} <-
              json_response(conn, 200)["data"]["workflows"],
            trigger <- triggers,
            into: %{} do
          {trigger["id"], Map.fetch(trigger, "custom_path")}
        end

      assert exported == expected_by_trigger_id
    end
  end
end
