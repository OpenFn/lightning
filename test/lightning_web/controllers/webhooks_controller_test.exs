defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

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

    test "returns 200 and the rejection reason when run soft limit has been reached",
         %{conn: conn} do
      Mox.stub(MockUsageLimiter, :limit_action, &StubUsageLimiter.limit_action/2)

      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      conn = post(conn, "/i/#{trigger.id}")

      response = json_response(conn, 200)

      assert %{"work_order_id" => work_order_id, "error" => "too_many_runs"} =
               response

      assert Ecto.UUID.dump(work_order_id)

      refute Map.has_key?(response, "message"),
             "the limiter's project-facing copy must not reach /i/*"

      work_order = WorkOrders.get(work_order_id, include: [:runs])
      assert work_order.state == :rejected
      assert work_order.runs == []
    end

    test "returns 429 when run limit has been reached", %{conn: conn} do
      Mox.stub(MockUsageLimiter, :limit_action, fn _action, _ctx ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn = post(conn, "/i/#{trigger.id}")

      assert json_response(conn, 429) == %{
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
                 {Tesla.Middleware.BaseUrl, LightningWeb.Endpoint.url()},
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

    test "creates a pending workorder from a project-namespaced custom path", %{
      conn: conn
    } do
      project = insert(:project)

      %{triggers: [%{id: trigger_id} = trigger]} =
        insert(:simple_workflow, project: project)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      {:ok, _} =
        trigger
        |> Lightning.Workflows.Trigger.changeset(%{
          custom_path: "et-emr-facility-001"
        })
        |> Repo.update()

      conn =
        post(conn, "/i/#{project.id}/et-emr-facility-001", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      assert %{trigger: %{id: ^trigger_id}, state: :pending} =
               WorkOrders.get(work_order_id, include: [:trigger])
    end

    test "the generated URL still works once a custom path is set", %{
      conn: conn
    } do
      project = insert(:project)

      %{triggers: [%{id: trigger_id} = trigger]} =
        insert(:simple_workflow, project: project)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      {:ok, _} =
        trigger
        |> Lightning.Workflows.Trigger.changeset(%{
          custom_path: "et-emr-facility-001"
        })
        |> Repo.update()

      conn = post(conn, "/i/#{trigger_id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      assert %{trigger: %{id: ^trigger_id}} =
               WorkOrders.get(work_order_id, include: [:trigger])
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

    test "waits for and returns the broadcast response body and status code", %{
      conn: conn
    } do
      %{triggers: [trigger], project_id: project_id} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      Lightning.WorkOrders.Events.subscribe(project_id)

      test_pid = self()

      task =
        Task.async(fn ->
          conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})
          send(test_pid, {:response, conn})
        end)

      assert_receive %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: work_order
      }

      assert_receive %Lightning.WorkOrders.Events.RunCreated{run: run}

      body = %{"result" => "success", "value" => 42}

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "work_order:#{work_order.id}:webhook_response",
        {:webhook_response, 200, body}
      )

      assert_receive {:response, response_conn}, 5_000

      assert json_response(response_conn, 200) == body

      assert get_resp_header(response_conn, "x-meta-work-order-id") == [
               work_order.id
             ]

      assert get_resp_header(response_conn, "x-meta-run-id") == [run.id]

      Task.await(task)
    end

    test "passes through any status code from the broadcast message", %{
      conn: conn
    } do
      %{triggers: [trigger], project_id: project_id} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      Lightning.WorkOrders.Events.subscribe(project_id)

      test_pid = self()

      task =
        Task.async(fn ->
          conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})
          send(test_pid, {:response, conn})
        end)

      assert_receive %Lightning.WorkOrders.Events.WorkOrderCreated{
        work_order: work_order
      }

      assert_receive %Lightning.WorkOrders.Events.RunCreated{run: run}

      body = %{"message" => "run failed"}

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "work_order:#{work_order.id}:webhook_response",
        {:webhook_response, 422, body}
      )

      assert_receive {:response, response_conn}, 5_000

      assert json_response(response_conn, 422) == body

      assert get_resp_header(response_conn, "x-meta-work-order-id") == [
               work_order.id
             ]

      assert get_resp_header(response_conn, "x-meta-run-id") == [run.id]

      Task.await(task)
    end

    test "returns timeout if workflow doesn't complete within timeout period", %{
      conn: conn
    } do
      expect(Lightning.MockConfig, :webhook_response_timeout_ms, fn -> 2_000 end)

      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

      [work_order_id] = get_resp_header(conn, "x-meta-work-order-id")

      assert json_response(conn, 504) == %{
               "error" => "timeout",
               "message" => "Workflow did not complete within timeout period",
               "work_order_id" => work_order_id
             }

      assert WorkOrders.get(work_order_id)
    end

    for status_code <- [204, 304] do
      test "sends empty body when broadcast status is #{status_code}", %{
        conn: conn
      } do
        %{triggers: [trigger], project_id: project_id} =
          insert(:simple_workflow)
          |> Lightning.Repo.preload(:triggers)
          |> with_snapshot()

        trigger =
          trigger
          |> Ecto.Changeset.change(webhook_reply: :after_completion)
          |> Repo.update!()

        Lightning.WorkOrders.Events.subscribe(project_id)

        test_pid = self()

        task =
          Task.async(fn ->
            conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})
            send(test_pid, {:response, conn})
          end)

        assert_receive %Lightning.WorkOrders.Events.WorkOrderCreated{
          work_order: work_order
        }

        assert_receive %Lightning.WorkOrders.Events.RunCreated{run: _run}

        Phoenix.PubSub.broadcast(
          Lightning.PubSub,
          "work_order:#{work_order.id}:webhook_response",
          {:webhook_response, unquote(status_code), nil}
        )

        assert_receive {:response, response_conn}, 5_000

        assert response_conn.status == unquote(status_code)
        assert response_conn.resp_body == ""

        Task.await(task)
      end
    end

    test "replies with the rejection instead of waiting when no run was created",
         %{conn: conn} do
      Mox.stub(MockUsageLimiter, :limit_action, &StubUsageLimiter.limit_action/2)

      Mox.stub(Lightning.MockConfig, :webhook_response_timeout_ms, fn ->
        60_000
      end)

      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      trigger
      |> Ecto.Changeset.change(webhook_reply: :after_completion)
      |> Repo.update!()

      {elapsed_us, conn} =
        :timer.tc(fn -> post(conn, "/i/#{trigger.id}", %{"foo" => "bar"}) end)

      assert elapsed_us < 5_000_000,
             "request waited on a response nothing can send"

      response = json_response(conn, 429)

      assert %{"error" => "too_many_runs", "work_order_id" => work_order_id} =
               response

      refute Map.has_key?(response, "message"),
             "the limiter's project-facing copy must not reach /i/*"

      work_order = WorkOrders.get(work_order_id, include: [:runs])
      assert work_order.state == :rejected
      assert work_order.runs == []
    end

    test "returns immediately when webhook_reply is :custom, which has no publisher",
         %{conn: conn} do
      Mox.stub(Lightning.MockConfig, :webhook_response_timeout_ms, fn ->
        60_000
      end)

      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      trigger
      |> Ecto.Changeset.change(webhook_reply: :custom)
      |> Repo.update!()

      {elapsed_us, conn} =
        :timer.tc(fn -> post(conn, "/i/#{trigger.id}", %{"foo" => "bar"}) end)

      assert elapsed_us < 5_000_000,
             "request waited on a response nothing can send"

      [work_order_id] = get_resp_header(conn, "x-meta-work-order-id")
      assert %{"work_order_id" => ^work_order_id} = json_response(conn, 200)
    end

    test "returns immediately when webhook_reply is before_start (default)", %{
      conn: conn
    } do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      assert trigger.webhook_reply == :before_start

      conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

      [work_order_id] = get_resp_header(conn, "x-meta-work-order-id")
      assert %{"work_order_id" => ^work_order_id} = json_response(conn, 200)
      assert WorkOrders.get(work_order_id)
    end
  end

  describe "sensitive request headers" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    test "the x-api-key consumed by webhook auth is not persisted in dataclip.request",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :api,
          api_key: "sup3r-s3cret-api-key"
        )

      associate_auth_methods(trigger, [auth_method])

      conn =
        conn
        |> put_req_header("x-api-key", "sup3r-s3cret-api-key")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["x-api-key"] == "[REDACTED]",
             "the api key Lightning already consumed to authenticate must not be retained"

      refute Runs.get_dataclip_request(run) =~ "sup3r-s3cret-api-key"
    end

    test "the Basic Authorization consumed by webhook auth is redacted from dataclip.request",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :basic,
          username: "caller",
          password: "sup3r-s3cret-password"
        )

      associate_auth_methods(trigger, [auth_method])

      credentials = Base.encode64("caller:sup3r-s3cret-password")

      conn =
        conn
        |> put_req_header("authorization", "Basic #{credentials}")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["authorization"] == "Basic [REDACTED]",
             "the Basic credentials Lightning already consumed must not be " <>
               "retained; the scheme is not a secret, so it stays legible"

      raw = Runs.get_dataclip_request(run)
      refute raw =~ credentials
      refute raw =~ "sup3r-s3cret-password"
    end

    test "a caller's own x-api-key survives when it is not the trigger's secret",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :basic,
          username: "caller",
          password: "sup3r-s3cret-password"
        )

      associate_auth_methods(trigger, [auth_method])

      credentials = Base.encode64("caller:sup3r-s3cret-password")

      conn =
        conn
        |> put_req_header("authorization", "Basic #{credentials}")
        |> put_req_header("x-api-key", "a-token-for-the-job-to-forward")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["authorization"] == "Basic [REDACTED]"

      assert request["headers"]["x-api-key"] ==
               "a-token-for-the-job-to-forward",
             "redaction is by value, not by header name: a token Lightning " <>
               "never consumed belongs to the caller and their job"
    end

    test "our api key is redacted from both headers webhook auth reads",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :api,
          api_key: "sup3r-s3cret-api-key"
        )

      associate_auth_methods(trigger, [auth_method])

      conn =
        conn
        |> put_req_header("x-api-key", "sup3r-s3cret-api-key")
        |> put_req_header("authorization", "Bearer sup3r-s3cret-api-key")
        |> put_req_header("x-copy-of-it", "sup3r-s3cret-api-key")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["x-api-key"] == "[REDACTED]"

      assert request["headers"]["authorization"] == "Bearer [REDACTED]",
             "auth matched on x-api-key, but the copy in the other header we " <>
               "read would otherwise be persisted intact"

      assert request["headers"]["x-copy-of-it"] == "sup3r-s3cret-api-key",
             "a header webhook auth does not read is passed through verbatim, " <>
               "secret-shaped or not"
    end

    test "cookie and proxy-authorization are redacted from dataclip.request",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      conn =
        conn
        |> put_req_header("cookie", "session=a-third-party-session-cookie")
        |> put_req_header("proxy-authorization", "Basic cHJveHk6c2VjcmV0")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["cookie"] == "[REDACTED]",
             "caller session cookies are a load-balancer/front-end concern, not run state"

      assert request["headers"]["proxy-authorization"] == "[REDACTED]"

      raw = Runs.get_dataclip_request(run)
      refute raw =~ "a-third-party-session-cookie"
      refute raw =~ "cHJveHk6c2VjcmV0"
    end

    test "non-sensitive caller headers are still passed through verbatim", %{
      conn: conn
    } do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      conn =
        conn
        |> put_req_header("x-request-id", "caller-supplied-id")
        |> put_req_header("user-agent", "acme-integration/1.2")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["x-request-id"] == "caller-supplied-id"
      assert request["headers"]["user-agent"] == "acme-integration/1.2"
    end
  end

  defp associate_auth_methods(trigger, auth_methods) do
    trigger
    |> Repo.preload(:webhook_auth_methods)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:webhook_auth_methods, auth_methods)
    |> Repo.update!()
  end
end
