defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

  import Ecto.Query
  import Lightning.Factories
  import Mox

  alias Lightning.Extensions.MockRateLimiter
  alias Lightning.Extensions.StubRateLimiter
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.StubUsageLimiter

  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.WorkOrders

  @moduletag capture_log: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub(Lightning.MockConfig, :cors_origin, fn -> "*" end)
    :ok
  end

  describe "a POST request to '/i'" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    test "returns 200 when run soft limit has been reached", %{conn: conn} do
      Mox.stub(MockUsageLimiter, :limit_action, &StubUsageLimiter.limit_action/2)

      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      conn = post(conn, "/i/#{trigger.id}")

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)
      assert Ecto.UUID.dump(work_order_id)
    end

    test "returns 402 when run limit has been reached", %{conn: conn} do
      Mox.stub(MockUsageLimiter, :limit_action, fn _action, _ctx ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn = post(conn, "/i/#{trigger.id}")

      assert json_response(conn, 402) == %{
               "error" => "runs_hard_limit",
               "message" => "Runs limit exceeded"
             }
    end

    test "returns 404 when trigger does not exist", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{"error" => "Webhook not found"}
    end

    test "returns 413 with a body exceeding the limit", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Repo.preload(:triggers)
        |> with_snapshot()

      Application.put_env(:lightning, :max_dataclip_size_bytes, 1_000_000)

      smaller_body =
        %{"data" => %{a: String.duplicate("a", 500_000)}}

      assert post(conn, "/i/#{trigger.id}", smaller_body)

      exceeding_body =
        %{"data" => %{a: String.duplicate("a", 2_000_000)}}

      assert {:ok, %Tesla.Env{status: 413, body: "Request Entity Too Large"}} =
               [
                 {Tesla.Middleware.BaseUrl, "http://localhost:4002"},
                 Tesla.Middleware.JSON
               ]
               |> Tesla.client()
               |> Tesla.post(
                 "/i/#{trigger.id}",
                 exceeding_body
               )
    end

    test "returns 429 on rate limiting", %{conn: conn} do
      Mox.stub(MockRateLimiter, :limit_request, &StubRateLimiter.limit_request/3)

      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn = post(conn, "/i/#{trigger.id}")

      assert json_response(conn, 429) == %{
               "error" => "too_many_requests",
               "message" => "Too many runs in the last minute"
             }
    end

    test "returns a 200 when a valid GET is sent", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn = get(conn, "/i/#{trigger_id}")

      assert json_response(conn, 200) == %{
               "message" =>
                 "OpenFn webhook trigger found. Make a POST request to execute this workflow."
             }
    end

    test "returns 404 when trigger does not exist for GET request", %{conn: conn} do
      non_existent_trigger_id = Ecto.UUID.generate()

      conn = get(conn, "/i/#{non_existent_trigger_id}")

      assert json_response(conn, 404) == %{"error" => "Webhook not found"}
    end

    test "returns 404 when trigger exists but is of type cron", %{conn: conn} do
      %{triggers: [trigger = %{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      # Change the trigger type to cron

      Ecto.Changeset.change(trigger, type: :cron)
      |> Lightning.Repo.update!()

      conn = get(conn, "/i/#{trigger_id}")

      assert json_response(conn, 404) == %{"error" => "Webhook not found"}
    end

    test "creates a pending workorder with a valid trigger", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger_id}", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      assert %{trigger: %{id: ^trigger_id}, runs: [run], state: :pending} =
               WorkOrders.get(work_order_id,
                 include: [:runs, :dataclip, :trigger]
               )

      assert %{starting_trigger_id: ^trigger_id} = run

      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 1

      assert Runs.get_dataclip_body(run) == ~s({"foo": "bar"})

      assert Runs.get_dataclip_request(run) ==
               ~s({\"path\": [\"i\", \"#{trigger_id}\"], \"method\": \"POST\", \"headers\": {\"content-type\": \"multipart/mixed; boundary=plug_conn_test\"}, \"query_params\": {}})
    end

    test "creates a pending workorder with a valid trigger and an additional path",
         %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger_id}/Patient", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      assert %{trigger: %{id: ^trigger_id}, runs: [run], state: :pending} =
               WorkOrders.get(work_order_id,
                 include: [:runs, :dataclip, :trigger]
               )

      assert %{starting_trigger_id: ^trigger_id} = run

      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 1

      assert Runs.get_dataclip_body(run) == ~s({"foo": "bar"})

      assert Runs.get_dataclip_request(run) ==
               ~s({\"path\": [\"i\", \"#{trigger_id}\", \"Patient\"], \"method\": \"POST\", \"headers\": {\"content-type\": \"multipart/mixed; boundary=plug_conn_test\"}, \"query_params\": {}})
    end

    test "creates a pending workorder with a valid trigger and some query params",
         %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger_id}?extra=stuff&moar=things", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      assert %{trigger: %{id: ^trigger_id}, runs: [run], state: :pending} =
               WorkOrders.get(work_order_id,
                 include: [:runs, :dataclip, :trigger]
               )

      assert %{starting_trigger_id: ^trigger_id} = run

      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 1

      assert Runs.get_dataclip_body(run) == ~s({"foo": "bar"})

      assert Runs.get_dataclip_request(run) ==
               ~s({\"path\": [\"i\", \"#{trigger_id}\"], \"method\": \"POST\", \"headers\": {\"content-type\": \"multipart/mixed; boundary=plug_conn_test\"}, \"query_params\": {\"moar\": \"things\", \"extra\": \"stuff\"}})
    end

    test "returns 415 when client sends xml", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn =
        conn
        |> put_req_header("content-type", "text/xml")
        |> put_req_header("accepts", "*/*")
        |> post("/i/#{trigger_id}", "{}")

      assert response(conn, 415) == ~s({"error":"Unsupported Media Type"})
    end
  end

  describe "a disabled message" do
    setup %{conn: conn} do
      trigger = insert(:trigger, enabled: false)

      [conn: conn, trigger_id: trigger.id, message: %{"foo" => "bar"}]
    end

    test "return 403 on a disabled message", %{
      conn: conn,
      trigger_id: trigger_id,
      message: message
    } do
      conn = post(conn, "/i/#{trigger_id}", message)

      assert %{"message" => response_message} = json_response(conn, 403)

      assert response_message =~
               "Unable to process request, trigger is disabled."
    end
  end

  describe "webhook DB retry behaviour" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    setup %{conn: conn} do
      Mimic.copy(Lightning.WorkOrders)

      Mox.stub(Lightning.MockConfig, :webhook_retry, fn ->
        [
          max_attempts: 1,
          initial_delay_ms: 0,
          max_delay_ms: 0,
          timeout_ms: 1_000,
          jitter: false
        ]
      end)

      Mox.stub(Lightning.MockConfig, :webhook_retry, fn
        :timeout_ms -> 1_000
        _ -> nil
      end)

      {:ok, %{conn: conn}}
    end

    test "returns 503 with Retry-After when DB connection errors are exhausted",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      Mimic.expect(Lightning.WorkOrders, :create_for, fn _trigger, _opts ->
        {:error, %DBConnection.ConnectionError{message: "db down"}}
      end)

      conn = post(conn, "/i/#{trigger.id}")

      assert json_response(conn, 503) == %{
               "error" => "service_unavailable",
               "message" =>
                 "Unable to process request due to temporary database issues. Please try again in 1s.",
               "retry_after" => 1
             }

      assert get_resp_header(conn, "retry-after") == ["1"]
    end

    test "retries once on DB error then succeeds", %{conn: conn} do
      Mox.stub(Lightning.MockConfig, :webhook_retry, fn ->
        [
          max_attempts: 2,
          initial_delay_ms: 0,
          max_delay_ms: 0,
          timeout_ms: 5_000,
          jitter: false
        ]
      end)

      Mox.stub(Lightning.MockConfig, :webhook_retry, fn
        :timeout_ms -> 5_000
        _ -> nil
      end)

      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      work_order_id = Ecto.UUID.generate()

      Mimic.expect(Lightning.WorkOrders, :create_for, fn _t, _o ->
        {:error, %DBConnection.ConnectionError{message: "flaky"}}
      end)

      Mimic.expect(Lightning.WorkOrders, :create_for, fn _t, _o ->
        {:ok, %{id: work_order_id}}
      end)

      conn = post(conn, "/i/#{trigger.id}")

      assert json_response(conn, 200) == %{"work_order_id" => work_order_id}
    end
  end

  describe "create/2 controller error branches (422 + nil fallback)" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    test "returns 422 invalid_request with details when WorkOrders.create_for returns a changeset error",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      bad_changeset =
        %Lightning.WorkOrder{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:dataclip, "is invalid")

      Mimic.copy(Lightning.WorkOrders)

      Mimic.expect(Lightning.WorkOrders, :create_for, fn _trigger, _opts ->
        {:error, bad_changeset}
      end)

      conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"error" => "invalid_request", "details" => details} =
               json_response(conn, 422)

      assert Map.has_key?(details, "dataclip")
    end

    test "returns 422 with atom reason when WorkOrders.create_for returns {:error, reason}",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      Mimic.copy(Lightning.WorkOrders)

      Mimic.expect(Lightning.WorkOrders, :create_for, fn _trigger, _opts ->
        {:error, :bad_payload}
      end)

      conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

      assert json_response(conn, 422) == %{"error" => "bad_payload"}
    end

    test "returns 404 when controller receives nil trigger assign (fallback path)" do
      # Call the controller action directly to bypass WebhookAuth plug,
      # so we actually execute the `nil -> 404` branch in the controller.
      conn = Phoenix.ConnTest.build_conn(:post, "/i/nonexistent")
      conn = LightningWeb.WebhooksController.create(conn, %{})

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "Webhook not found"}
    end
  end

  describe "delayed webhook response (webhook_reply: :after_completion)" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    test "waits for and returns the final state on success", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      # Update trigger to use after_completion
      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      message = %{"foo" => "bar"}

      # Spawn a task that will post to the webhook
      # This task will be blocked waiting for the webhook response
      test_pid = self()

      task =
        Task.async(fn ->
          conn = post(conn, "/i/#{trigger.id}", message)
          send(test_pid, {:response, conn})
        end)

      # Wait for the work order to be created
      Process.sleep(100)

      # Find the work order
      work_order =
        Lightning.Repo.one(
          from wo in Lightning.WorkOrder,
            where: wo.trigger_id == ^trigger.id,
            order_by: [desc: wo.inserted_at],
            limit: 1
        )

      assert work_order

      # Get the run for metadata
      run =
        Lightning.Repo.one(
          from r in Lightning.Run,
            where: r.work_order_id == ^work_order.id,
            limit: 1
        )

      # Simulate the worker completing the run with final state
      final_state_data = %{"result" => "success", "data" => %{"x" => 42}}

      response_body = %{
        data: final_state_data,
        meta: %{
          work_order_id: work_order.id,
          run_id: run.id,
          state: :success,
          error_type: nil,
          inserted_at: run.inserted_at,
          started_at: run.started_at,
          claimed_at: run.claimed_at,
          finished_at: run.finished_at
        }
      }

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "work_order:#{work_order.id}:webhook_response",
        {:webhook_response, 200, response_body}
      )

      # Now the task should complete with the response
      assert_receive {:response, response_conn}, 5_000

      response = json_response(response_conn, 200)
      assert response["data"] == final_state_data
      assert response["meta"]["work_order_id"] == work_order.id
      assert response["meta"]["run_id"] == run.id
      assert response["meta"]["state"] == "success"

      Task.await(task)
    end

    test "waits for and returns error state on failure", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      message = %{"foo" => "bar"}
      test_pid = self()

      task =
        Task.async(fn ->
          conn = post(conn, "/i/#{trigger.id}", message)
          send(test_pid, {:response, conn})
        end)

      Process.sleep(100)

      work_order =
        Lightning.Repo.one(
          from wo in Lightning.WorkOrder,
            where: wo.trigger_id == ^trigger.id,
            order_by: [desc: wo.inserted_at],
            limit: 1
        )

      assert work_order

      # Get the run for metadata
      run =
        Lightning.Repo.one(
          from r in Lightning.Run,
            where: r.work_order_id == ^work_order.id,
            limit: 1
        )

      error_data = %{"error" => "Something went wrong"}

      response_body = %{
        data: error_data,
        meta: %{
          work_order_id: work_order.id,
          run_id: run.id,
          state: :failed,
          error_type: "RuntimeError",
          inserted_at: run.inserted_at,
          started_at: run.started_at,
          claimed_at: run.claimed_at,
          finished_at: run.finished_at
        }
      }

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "work_order:#{work_order.id}:webhook_response",
        {:webhook_response, 422, response_body}
      )

      assert_receive {:response, response_conn}, 5_000

      response = json_response(response_conn, 422)
      assert response["data"] == error_data
      assert response["meta"]["work_order_id"] == work_order.id
      assert response["meta"]["run_id"] == run.id
      assert response["meta"]["state"] == "failed"
      assert response["meta"]["error_type"] == "RuntimeError"

      Task.await(task)
    end

    test "returns timeout if workflow doesn't complete within timeout period", %{
      conn: conn
    } do
      # Set a shorter timeout for this test (2 seconds instead of default)
      expect(Lightning.MockConfig, :webhook_response_timeout_ms, fn -> 2_000 end)

      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      message = %{"foo" => "bar"}

      # This will timeout since we never broadcast a response
      conn = post(conn, "/i/#{trigger.id}", message)

      assert json_response(conn, 504) == %{
               "error" => "timeout",
               "message" => "Workflow did not complete within timeout period",
               "work_order_id" => json_response(conn, 504)["work_order_id"]
             }

      # Verify work order was still created
      work_order_id = json_response(conn, 504)["work_order_id"]
      assert WorkOrders.get(work_order_id)
    end

    test "returns immediately when webhook_reply is before_start (default)", %{
      conn: conn
    } do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      # Ensure trigger is using default before_start
      assert trigger.webhook_reply == :before_start

      message = %{"foo" => "bar"}

      # Should return immediately
      conn = post(conn, "/i/#{trigger.id}", message)

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)
      assert WorkOrders.get(work_order_id)
    end
  end
end
