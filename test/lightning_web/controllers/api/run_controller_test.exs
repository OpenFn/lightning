defmodule LightningWeb.API.RunControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.InvocationFixtures
  import Lightning.WorkflowsFixtures
  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/runs")

    assert %{"error" => "Unauthorized"} == json_response(conn, 401)
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "Oooops"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/runs")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_run]

    defp pluck_id(data) do
      Map.get(data, "id") || Map.get(data, :id)
    end

    test "lists all runs for a project I belong to", %{
      conn: conn,
      project: project
    } do
      other_project = project_fixture()
      runs = Enum.map(0..10, fn _ -> run_fixture(project_id: project.id) end)

      other_runs =
        Enum.map(0..2, fn _ -> run_fixture(project_id: other_project.id) end)

      conn = get(conn, ~p"/api/projects/#{project.id}/runs?#{%{page_size: 2}}")

      response = json_response(conn, 200)

      all_run_ids = MapSet.new(runs |> Enum.map(&pluck_id/1))
      returned_run_ids = MapSet.new(response["data"] |> Enum.map(&pluck_id/1))

      assert MapSet.subset?(returned_run_ids, all_run_ids)

      other_run_ids = MapSet.new(other_runs |> Enum.map(&pluck_id/1))

      refute MapSet.subset?(other_run_ids, all_run_ids)
    end

    test "responds with a 401 when I don't have access", %{conn: conn} do
      other_project = project_fixture()

      conn = get(conn, ~p"/api/projects/#{other_project.id}/runs")

      response = json_response(conn, 401)

      assert response == %{"error" => "Unauthorized"}
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
      step_id = run.id

      assert %{
               "attributes" => %{
                 "finished_at" => nil
               },
               "id" => ^step_id,
               "links" => %{
                 "self" => _
               },
               "relationships" => %{},
               "type" => "runs"
             } = response["data"]
    end
  end

  # TODO: see if we can't use run fixture
  defp create_run(%{project: project}) do
    job = job_fixture(workflow_id: workflow_fixture(project_id: project.id).id)
    %{run: run_fixture(job_id: job.id)}
  end
end
