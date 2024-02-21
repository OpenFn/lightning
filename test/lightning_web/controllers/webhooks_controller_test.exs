defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Mock

  alias Lightning.Extensions.RateLimiter
  alias Lightning.Extensions.UsageLimiter
  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.WorkOrders

  require Record
  @fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @fields)

  describe "a POST request to '/i'" do
    test "returns 404 when trigger does not exist", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{"error" => "Webhook not found"}
    end

    test "returns 413 with a body exceeding the limit" do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

      Application.put_env(:lightning, :max_dataclip_size_bytes, 1_000_000)

      smaller_body =
        %{"data" => %{a: String.duplicate("a", 500_000)}}

      assert {:ok, %Tesla.Env{status: 200}} =
               [
                 {Tesla.Middleware.BaseUrl, "http://localhost:4002"},
                 Tesla.Middleware.JSON
               ]
               |> Tesla.client()
               |> Tesla.post(
                 "/i/#{trigger.id}",
                 smaller_body
               )

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
      with_mock RateLimiter,
        limit_request: fn _conn, _context, _opts ->
          {:error, :too_many_requests,
           %{text: "Too many work orders in the last minute"}}
        end do
        %{triggers: [trigger]} =
          insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

        conn = post(conn, "/i/#{trigger.id}")

        assert json_response(conn, 429) == %{
                 "error" => "Too many work orders in the last minute"
               }
      end
    end

    test "returns 429 on usage limiting", %{conn: conn} do
      with_mock UsageLimiter,
        limit_action: fn _action, _context ->
          {:error, :too_many_runs, %{text: "Runs limit exceeded"}}
        end do
        %{triggers: [trigger]} =
          insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

        conn = post(conn, "/i/#{trigger.id}")
        assert json_response(conn, 429) == %{"error" => "Runs limit exceeded"}
      end
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
               ~s({"headers": {"content-type": "multipart/mixed; boundary=plug_conn_test"}})
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
