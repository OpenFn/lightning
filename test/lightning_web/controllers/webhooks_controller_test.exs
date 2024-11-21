defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories

  alias Lightning.Extensions.MockRateLimiter
  alias Lightning.Extensions.StubRateLimiter
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.StubUsageLimiter

  alias Lightning.Auditing.Audit
  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.WorkOrders

  require Record
  @fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @fields)

  describe "a POST request to '/i'" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    test "returns 200 when run soft limit has been reached", %{conn: conn} do
      Mox.stub(MockUsageLimiter, :limit_action, &StubUsageLimiter.limit_action/2)

      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

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
               "error" => "Runs limit exceeded"
             }
    end

    test "returns 404 when trigger does not exist", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{"error" => "Webhook not found"}
    end

    test "returns 413 with a body exceeding the limit", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

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
               "error" => "Too many runs in the last minute"
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

    test "creates a pending workorder with a valid trigger", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

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
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

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
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

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

    test "assigns the trigger as the actor for the audit event", %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      message = %{"foo" => "bar"}
      post(conn, "/i/#{trigger_id}", message)

      assert %{actor_id: ^trigger_id} = Repo.one!(Audit)
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
end
