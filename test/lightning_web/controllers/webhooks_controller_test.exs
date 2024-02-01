defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.WorkOrders

  import Lightning.Factories

  require Record
  @fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @fields)

  describe "a POST request to '/i'" do
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

    test "with a valid trigger id instantiates a workorder", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger.id}", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 1

      work_order =
        %{runs: [run]} =
        WorkOrders.get(work_order_id, include: [:runs, :dataclip, :trigger])

      assert work_order.trigger.id == trigger.id

      assert Runs.get_dataclip_body(run) == ~s({"foo": "bar"})

      assert Runs.get_dataclip_request(run) ==
               ~s({"headers": {"content-type": "multipart/mixed; boundary=plug_conn_test"}})

      %{runs: [run]} = work_order
      assert run.starting_trigger_id == trigger.id
    end

    test "with an invalid trigger id returns a 404", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{"error" => "Webhook not found"}
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
