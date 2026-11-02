defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Mox
  import LightningWeb.API.ProblemHelpers

  alias Lightning.Extensions.MockRateLimiter
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.StubRateLimiter

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

    test "returns 404 when trigger does not exist", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert_problem(conn, 404, :not_found, [])
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

      assert {:ok,
              %Tesla.Env{
                status: 413,
                body: %{"status" => 413, "code" => "content_too_large"}
              }} =
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

    test "returns a 200 and the trigger-found message when a valid GET is sent",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

      conn = get(conn, "/i/#{trigger.id}")

      assert conn.status == 200

      assert conn.resp_body ==
               ~s({"message":"OpenFn webhook trigger found. Make a POST request to execute this workflow."})
    end

    test "returns 404 when trigger does not exist for GET request", %{conn: conn} do
      non_existent_trigger_id = Ecto.UUID.generate()

      conn = get(conn, "/i/#{non_existent_trigger_id}")

      assert_problem(conn, 404, :not_found, [])
    end

    test "returns 404 when trigger exists but is of type cron", %{conn: conn} do
      %{triggers: [trigger = %{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      # Change the trigger type to cron

      Ecto.Changeset.change(trigger, type: :cron)
      |> Lightning.Repo.update!()

      conn = get(conn, "/i/#{trigger_id}")

      assert_problem(conn, 404, :not_found, [])
    end

    test "creates a pending workorder with a valid trigger", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger_id}", message)

      assert conn.status == 200

      [work_order_id] = get_resp_header(conn, "x-meta-work-order-id")
      assert conn.resp_body == ~s({"work_order_id":"#{work_order_id}"})

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

    test "returns 415 when client sends xml", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn =
        conn
        |> put_req_header("content-type", "text/xml")
        |> put_req_header("accepts", "*/*")
        |> post("/i/#{trigger_id}", "{}")

      assert_problem(conn, 415, :unsupported_media_type, [])
    end

    test "returns 400 malformed for a body that isn't JSON", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/i/#{trigger_id}", ~s({"foo": ))
      |> assert_problem(400, :malformed, [])
    end

    test "returns 400 bad_request for a form body that isn't UTF-8", %{
      conn: conn
    } do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/i/#{trigger_id}", "a=%FF")
      |> assert_problem(400, :bad_request, [])
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

      assert_problem(conn, 403, :trigger_disabled, [])
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

      assert_problem(conn, 503, :service_unavailable, [])
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

    test "returns 422 invalid with one entry at the body when the work order can't be saved",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

      assert_problem(conn, 422, :invalid, [
        %{"pointer" => "#", "code" => "invalid", "detail" => "is invalid"}
      ])

      assert Repo.aggregate(Lightning.WorkOrder, :count) == 0
    end

    test "returns 404 when controller receives nil trigger assign (fallback path)" do
      # Call the controller action directly to bypass WebhookAuth plug,
      # so we actually execute the `nil -> 404` branch in the controller.
      conn = Phoenix.ConnTest.build_conn(:post, "/i/nonexistent")
      conn = LightningWeb.WebhooksController.create(conn, %{})

      assert_problem(conn, 404, :not_found, [])
    end
  end

  describe "the challenges on a 401" do
    for {types, challenges} <- [
          {[:basic], []},
          {[:api], [~s(ApiKey header="x-api-key")]},
          {[:api, :basic], [~s(ApiKey header="x-api-key")]}
        ] do
      test "offer an API key, never Basic, on a trigger with #{inspect(types)} methods",
           %{conn: conn} do
        %{triggers: [trigger]} =
          insert(:simple_workflow) |> Repo.preload(:triggers)

        methods =
          for type <- unquote(types),
              do: insert(:webhook_auth_method, auth_type: type, api_key: "key")

        associate_auth_methods(trigger, methods)

        conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

        assert_unauthenticated(conn, :unauthenticated, unquote(challenges))
      end
    end
  end

  describe "a limiter's refusal" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    setup do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers) |> with_snapshot()

      %{trigger: trigger}
    end

    test "gets the usage limiter's 429, with the code by reason",
         %{conn: conn, trigger: trigger} do
      for reason <- [
            :runs_hard_limit,
            :exceeds_limit,
            :unknown_project,
            :runs_cap_exceeded
          ] do
        Mox.stub(MockUsageLimiter, :limit_action, fn _action, _context ->
          {:error, reason, %Lightning.Extensions.Message{text: "upgrade"}}
        end)

        conn = post(conn, "/i/#{trigger.id}")

        body = assert_problem(conn, 429, :exceeds_limit, [])
        refute Map.has_key?(body, "message")
      end
    end

    test "gets the rate limiter's 429, with no Retry-After",
         %{conn: conn, trigger: trigger} do
      Mox.stub(MockRateLimiter, :limit_request, &StubRateLimiter.limit_request/3)

      conn = post(conn, "/i/#{trigger.id}")

      body = assert_problem(conn, 429, :too_many_requests, [])
      refute Map.has_key?(body, "message")
      assert get_resp_header(conn, "retry-after") == []
    end

    test "gets a synchronous trigger's 429, with its work order",
         %{conn: conn, trigger: trigger} do
      Mox.stub(MockUsageLimiter, :limit_action, fn _action, _context ->
        {:error, :too_many_runs, %Lightning.Extensions.Message{text: "wait"}}
      end)

      trigger
      |> Ecto.Changeset.change(webhook_reply: :after_completion)
      |> Repo.update!()

      conn = post(conn, "/i/#{trigger.id}")

      body = assert_problem(conn, 429, :too_many_runs, [])

      assert [body["work_order_id"]] ==
               get_resp_header(conn, "x-meta-work-order-id")
    end

    # The work order was saved, so this is a success, and a header that says to
    # retry would make senders save it again.
    test "gets the asynchronous 200 with error, byte for byte, and no Retry-After",
         %{conn: conn, trigger: trigger} do
      Mox.stub(MockUsageLimiter, :limit_action, fn _action, _context ->
        {:error, :too_many_runs, %Lightning.Extensions.Message{text: "wait"}}
      end)

      conn = post(conn, "/i/#{trigger.id}")

      [work_order_id] = get_resp_header(conn, "x-meta-work-order-id")

      assert conn.status == 200

      assert conn.resp_body ==
               ~s({"error":"too_many_runs","work_order_id":"#{work_order_id}"})

      assert get_resp_header(conn, "content-type") == [
               "application/json; charset=utf-8"
             ]

      assert get_resp_header(conn, "retry-after") == []

      work_order = WorkOrders.get(work_order_id, include: [:runs])
      assert work_order.state == :rejected
      assert work_order.runs == []
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
