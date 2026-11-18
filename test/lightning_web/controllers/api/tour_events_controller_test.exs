defmodule LightningWeb.API.TourEventsControllerTest do
  use LightningWeb.ConnCase, async: true

  @events ~w(button_shown button_clicked tour_started tour_completed
             tour_abandoned spotlight_shown notice_shown)

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "create without authentication" do
    test "is rejected with a 401", %{conn: conn} do
      conn = post(conn, ~p"/api/tour_events", %{"event" => "tour_started"})

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "create" do
    setup [:register_and_log_in_user]

    setup do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :ui, :tour]
        ])

      [ref: ref]
    end

    test "accepts every whitelisted event and emits telemetry", %{
      conn: conn,
      ref: ref,
      user: %{id: user_id}
    } do
      for event <- @events do
        conn = post(conn, ~p"/api/tour_events", %{"event" => event})

        assert response(conn, 204)

        assert_receive {[:lightning, :ui, :tour], ^ref, %{count: 1},
                        %{event: ^event, user_id: ^user_id}}
      end
    end

    test "forwards the optional fields as telemetry metadata", %{
      conn: conn,
      ref: ref,
      user: %{id: user_id}
    } do
      conn =
        post(conn, ~p"/api/tour_events", %{
          "event" => "tour_abandoned",
          "page" => "workflow_edit",
          "element" => "run-button",
          "tab" => "vcs",
          "reason" => "closed",
          "step_index" => 2,
          "steps_total" => 5
        })

      assert response(conn, 204)

      assert_receive {[:lightning, :ui, :tour], ^ref, %{count: 1},
                      %{
                        event: "tour_abandoned",
                        page: "workflow_edit",
                        element: "run-button",
                        tab: "vcs",
                        reason: "closed",
                        step_index: 2,
                        steps_total: 5,
                        user_id: ^user_id
                      }}
    end

    test "rejects an unknown event", %{conn: conn, ref: ref} do
      conn = post(conn, ~p"/api/tour_events", %{"event" => "clicked_stuff"})

      assert json_response(conn, 400) == %{"error" => "unknown event"}
      refute_receive {[:lightning, :ui, :tour], ^ref, _, _}
    end

    test "rejects a request without an event", %{conn: conn, ref: ref} do
      conn = post(conn, ~p"/api/tour_events", %{"page" => "workflow_edit"})

      assert json_response(conn, 400) == %{"error" => "event is required"}
      refute_receive {[:lightning, :ui, :tour], ^ref, _, _}
    end

    test "rejects a malformed string field", %{conn: conn, ref: ref} do
      conn =
        post(conn, ~p"/api/tour_events", %{
          "event" => "tour_started",
          "page" => 42
        })

      assert json_response(conn, 400) == %{"error" => "page must be a string"}
      refute_receive {[:lightning, :ui, :tour], ^ref, _, _}
    end

    test "rejects a malformed integer field", %{conn: conn, ref: ref} do
      conn =
        post(conn, ~p"/api/tour_events", %{
          "event" => "tour_completed",
          "step_index" => "two"
        })

      assert json_response(conn, 400) == %{
               "error" => "step_index must be an integer"
             }

      refute_receive {[:lightning, :ui, :tour], ^ref, _, _}
    end
  end
end
