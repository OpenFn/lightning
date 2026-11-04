defmodule LightningWeb.WebhooksControllerReplyTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Mox
  import LightningWeb.API.ProblemHelpers

  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.StubUsageLimiter

  alias Lightning.Repo
  alias Lightning.WorkOrders

  @moduletag capture_log: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub(Lightning.MockConfig, :cors_origin, fn -> "*" end)
    :ok
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

      reply_to_webhook(work_order, 200, body)

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

      reply_to_webhook(work_order, 422, body)

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

      body = assert_problem(conn, 504, :timeout, [])
      assert body["work_order_id"] == work_order_id

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

        reply_to_webhook(work_order, unquote(status_code), nil)

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

      response = assert_problem(conn, 429, :too_many_runs, [])
      work_order_id = response["work_order_id"]

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

  # The controller subscribes only after the work order and run exist, so a
  # reply sent on RunCreated can arrive before anyone is listening.
  defp reply_to_webhook(work_order, status, body) do
    topic = "work_order:#{work_order.id}:webhook_response"
    await_subscriber(topic, 100)

    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      topic,
      {:webhook_response, status, body}
    )
  end

  defp await_subscriber(topic, 0),
    do: flunk("no subscriber on #{topic} after 1s")

  defp await_subscriber(topic, attempts) do
    # Phoenix.PubSub keeps subscribers in a Registry named after the server.
    if Registry.lookup(Lightning.PubSub, topic) == [] do
      Process.sleep(10)
      await_subscriber(topic, attempts - 1)
    end
  end
end
