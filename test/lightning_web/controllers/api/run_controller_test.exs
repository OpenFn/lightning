defmodule LightningWeb.API.RunControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.InvocationFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_run]

    test "lists all runs (via projects)", %{
      conn: conn,
      project: project
    } do
      runs = Enum.map(1..11, fn _ -> create_run(%{project: project}).run end)

      conn =
        get(
          conn,
          Routes.api_project_run_path(conn, :index, project.id, %{
            "page_size" => 2
          })
        )

      response = json_response(conn, 200)

      runs
      |> Enum.each(fn r ->
        response["data"] |> Enum.any?(fn d -> d["id"] == r.id end)
      end)
    end

    test "lists all runs for the current user", %{
      conn: conn,
      project: project,
      run: run
    } do
      runs = [create_run(%{project: project}).run, run]
      other_run = run_fixture()

      conn =
        get(
          conn,
          Routes.api_run_path(conn, :index, %{
            "page_size" => 3
          })
        )

      response = json_response(conn, 200)

      runs
      |> Enum.each(fn r ->
        assert response["data"] |> Enum.any?(fn d -> d["id"] == r.id end)
      end)

      refute response["data"] |> Enum.any?(fn d -> d["id"] == other_run.id end)
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_run]

    test "shows the run", %{conn: conn, run: run} do
      conn =
        get(
          conn,
          Routes.api_run_path(conn, :show, run, %{
            "fields" => %{"runs" => "exit_code,finished_at"}
          })
        )

      response = json_response(conn, 200)
      run_id = run.id

      assert %{
               "attributes" => %{
                 "exit_code" => nil,
                 "finished_at" => nil
               },
               "id" => ^run_id,
               "links" => %{
                 "self" => _
               },
               "relationships" => %{},
               "type" => "runs"
             } = response["data"]
    end
  end

  defp create_run(%{project: project}) do
    event = event_fixture(project_id: project.id)
    %{run: run_fixture(event_id: event.id)}
  end
end
