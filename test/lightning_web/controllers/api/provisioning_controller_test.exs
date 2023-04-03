defmodule LightningWeb.API.ProvisioningControllerTest do
  use LightningWeb.ConnCase, async: true

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "create" do
    setup [:assign_bearer_for_api]

    test "works", %{conn: conn} do
      conn =
        conn
        |> post(~p"/api/provision", project_data())

      response = json_response(conn, 200)
    end
  end

  defp project_data() do
    %{
      "name" => "myproject",
      "workflows" => [
        %{
          "key" => "workflow1",
          "name" => "workflow1",
          "jobs" => [
            %{
              "name" => "job1",
              "trigger" => %{"type" => "webhook"},
              "adaptor" => "language-fhir",
              "enabled" => true,
              "credential" => "abc",
              "body" => "fn(state => state)"
            }
          ]
        },
        %{
          "key" => "workflow2",
          "name" => "workflow2",
          "jobs" => [
            %{
              "name" => "job222",
              "trigger" => %{"type" => "webhook"},
              "adaptor" => "language-fhir",
              "enabled" => true,
              "credential" => "abc",
              "body" => "fn(state => state)"
            }
          ]
        }
      ]
    }
  end
end
