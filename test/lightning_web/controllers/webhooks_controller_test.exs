defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false

  alias Lightning.Attempts
  alias Lightning.WorkOrders

  import Lightning.Factories

  require Record
  @fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @fields)

  describe "a POST request to '/i'" do
    test "with a valid trigger id instantiates a workorder", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger.id}", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      work_order =
        %{attempts: [attempt]} =
        WorkOrders.get(work_order_id, include: [:attempts, :dataclip, :trigger])

      assert work_order.trigger.id == trigger.id

      assert Attempts.get_dataclip_body(attempt) == ~s({"foo": "bar"})

      %{attempts: [attempt]} = work_order
      assert attempt.starting_trigger_id == trigger.id
    end

    test "triggers a custom telemetry event", %{conn: conn} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :workorder, :webhook, :stop]
        ])

      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      trigger_id = trigger.id
      message = %{"foo" => "bar"}

      post(conn, "/i/#{trigger_id}", message)

      assert_received {
        [:lightning, :workorder, :webhook, :stop],
        ^ref,
        %{},
        %{path: ^trigger_id, status: :ok}
      }
    end

    test "executes a custom OpenTelemetry trace", %{conn: conn} do
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      trigger_id = trigger.id
      message = %{"foo" => "bar"}

      attributes =
        :otel_attributes.new([path: trigger_id], 128, :infinity)

      post(conn, "/i/#{trigger_id}", message)

      assert_receive {:span,
                      span(
                        name: "lightning.api.webhook",
                        attributes: ^attributes
                      )}
    end

    test "with an invalid trigger id returns a 404", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{"error" => "Webhook not found"}
    end

    test "with an invalid trigger id - indicates this in the telemetry span", %{
      conn: conn
    } do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :workorder, :webhook, :stop]
        ])

      post(conn, "/i/bar")

      assert_received {
        [:lightning, :workorder, :webhook, :stop],
        ^ref,
        %{},
        %{path: "bar", status: :not_found}
      }
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

    test "adjusts the telemetry span status", %{
      conn: conn,
      trigger_id: trigger_id,
      message: message
    } do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :workorder, :webhook, :stop]
        ])

      post(conn, "/i/#{trigger_id}", message)

      assert_received {
        [:lightning, :workorder, :webhook, :stop],
        ^ref,
        %{},
        %{path: ^trigger_id, status: :forbidden}
      }
    end
  end
end
