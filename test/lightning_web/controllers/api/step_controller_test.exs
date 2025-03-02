defmodule LightningWeb.API.StepControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ProjectsFixtures

  alias Lightning.Invocation.Step

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists all project steps for the current user", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job]} = insert(:simple_workflow, project: project)

      steps = insert_list(6, :step, job: job)

      assert response_steps =
               get(conn, ~p"/api/projects/#{project.id}/steps/")
               |> json_response(200)

      assert MapSet.equal?(
               MapSet.new(response_steps, & &1["id"]),
               MapSet.new(steps, & &1.id)
             )

      step_id = List.last(steps).id
      updated_at = DateTime.to_iso8601(List.last(steps).updated_at)
      processRef = "#{job.name}:1:#{job.id}"

      assert %{
               "id" => ^step_id,
               "processRef" => ^processRef,
               "initTime" => nil,
               "state" => "Ready",
               "lastChangeTime" => ^updated_at
             } = hd(response_steps)
    end

    test "lists a limited page of project steps for the current user", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job]} = insert(:simple_workflow, project: project)

      steps = insert_list(6, :step, job: job)

      conn = get(conn, ~p"/api/projects/#{project.id}/steps/", page_size: 5)

      assert response_steps = json_response(conn, 200)

      steps_ids = Enum.map(steps, & &1.id)

      assert Enum.all?(response_steps, &(&1["id"] in steps_ids))
    end

    test "lists a second page of project steps for the current user", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job]} = insert(:simple_workflow, project: project)

      steps = insert_list(9, :step, job: job) |> Enum.take(4)

      conn =
        get(conn, ~p"/api/projects/#{project.id}/steps/", page: 2, page_size: 5)

      assert response_steps = json_response(conn, 200)

      steps_ids = Enum.map(steps, & &1.id)

      assert Enum.all?(response_steps, &(&1["id"] in steps_ids))
    end

    test "lists no more steps than max size of a page", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job]} = insert(:simple_workflow, project: project)

      steps = insert_list(11, :step, job: job) |> Enum.drop(1)

      page_size =
        Application.get_env(:lightning, LightningWeb.API.StepController)[
          :max_page_size
        ]

      conn =
        get(conn, ~p"/api/projects/#{project.id}/steps/",
          page_size: page_size + 1
        )

      assert response_steps = json_response(conn, 200)

      steps_ids = Enum.map(steps, & &1.id)

      assert Enum.all?(response_steps, &(&1["id"] in steps_ids))
    end

    test "returns 400 on invalid param", %{conn: conn, project: project} do
      assert %{"error" => "Bad Request"} =
               conn
               |> get(~p"/api/projects/#{project.id}/steps", page: "1.1")
               |> json_response(400)

      assert %{"error" => "Bad Request"} =
               conn
               |> get(~p"/api/projects/#{project.id}/steps", pagen: "1")
               |> json_response(400)
    end

    test "returns 401 on unrelated project", %{conn: conn} do
      other_project = project_fixture()

      conn = get(conn, ~p"/api/projects/#{other_project.id}/steps")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "returns 401 on invalid token", %{conn: conn, project: project} do
      token =
        Lightning.Tokens.PersonalAccessToken.generate_and_sign!(
          %{"sub" => "user:#{Ecto.UUID.generate()}"},
          Lightning.Config.token_signer()
        )

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/projects/#{project.id}/steps")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "returns a successful step/process instance in all transitions", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job]} = insert(:simple_workflow, project: project)
      %{id: step_id, updated_at: updated_at} = insert(:step, job: job)

      updated_at = DateTime.to_iso8601(updated_at)
      processRef = "#{job.name}:1:#{job.id}"

      assert %{
               "id" => ^step_id,
               "initTime" => nil,
               "lastChangeTime" => ^updated_at,
               "processRef" => ^processRef,
               "state" => "Ready"
             } =
               conn
               |> get(~p"/api/projects/#{project.id}/steps/#{step_id}")
               |> json_response(200)

      %{started_at: started_at, updated_at: updated_at} =
        Step
        |> Repo.get!(step_id)
        |> Ecto.Changeset.change(%{id: step_id, started_at: DateTime.utc_now()})
        |> Repo.update!()

      started_at = DateTime.to_iso8601(started_at)
      updated_at = DateTime.to_iso8601(updated_at)

      assert %{
               "id" => ^step_id,
               "initTime" => ^started_at,
               "lastChangeTime" => ^updated_at,
               "processRef" => ^processRef,
               "state" => "Active"
             } =
               conn
               |> get(~p"/api/projects/#{project.id}/steps/#{step_id}")
               |> json_response(200)

      %{updated_at: updated_at} =
        Step
        |> Repo.get!(step_id)
        |> Ecto.Changeset.change(%{
          id: step_id,
          finished_at: DateTime.utc_now(),
          exit_reason: "sucess"
        })
        |> Repo.update!()

      updated_at = DateTime.to_iso8601(updated_at)

      assert %{
               "id" => ^step_id,
               "initTime" => ^started_at,
               "lastChangeTime" => ^updated_at,
               "processRef" => ^processRef,
               "state" => "Completed"
             } =
               conn
               |> get(~p"/api/projects/#{project.id}/steps/#{step_id}")
               |> json_response(200)
    end

    test "returns a step/process instance that was terminated", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job]} = insert(:simple_workflow, project: project)

      %{id: step_id, started_at: started_at, updated_at: updated_at} =
        insert(:step,
          started_at: DateTime.utc_now(),
          exit_reason: "kill",
          job: job
        )

      started_at = DateTime.to_iso8601(started_at)
      updated_at = DateTime.to_iso8601(updated_at)
      processRef = "#{job.name}:1:#{job.id}"

      assert %{
               "id" => ^step_id,
               "initTime" => ^started_at,
               "lastChangeTime" => ^updated_at,
               "processRef" => ^processRef,
               "state" => "Terminated"
             } =
               conn
               |> get(~p"/api/projects/#{project.id}/steps/#{step_id}")
               |> json_response(200)

      %{updated_at: updated_at} =
        Step
        |> Repo.get!(step_id)
        |> Ecto.Changeset.change(%{
          id: step_id,
          finished_at: DateTime.utc_now(),
          exit_reason: "cancel"
        })
        |> Repo.update!()

      updated_at = DateTime.to_iso8601(updated_at)

      assert %{
               "id" => ^step_id,
               "initTime" => ^started_at,
               "lastChangeTime" => ^updated_at,
               "processRef" => ^processRef,
               "state" => "Terminated"
             } =
               conn
               |> get(~p"/api/projects/#{project.id}/steps/#{step_id}")
               |> json_response(200)
    end

    test "returns a step/process instance that failed", %{
      conn: conn,
      project: project
    } do
      %{jobs: [job]} = insert(:simple_workflow, project: project)

      %{id: step_id, started_at: started_at, updated_at: updated_at} =
        insert(:step,
          started_at: DateTime.utc_now(),
          finished_at: DateTime.utc_now(),
          exit_reason: "fail",
          job: job
        )

      started_at = DateTime.to_iso8601(started_at)
      updated_at = DateTime.to_iso8601(updated_at)
      processRef = "#{job.name}:1:#{job.id}"

      assert %{
               "id" => ^step_id,
               "initTime" => ^started_at,
               "lastChangeTime" => ^updated_at,
               "processRef" => ^processRef,
               "state" => "Failed"
             } =
               conn
               |> get(~p"/api/projects/#{project.id}/steps/#{step_id}")
               |> json_response(200)

      %{updated_at: updated_at} =
        Step
        |> Repo.get!(step_id)
        |> Ecto.Changeset.change(%{
          id: step_id,
          finished_at: DateTime.utc_now(),
          exit_reason: "exception"
        })
        |> Repo.update!()

      updated_at = DateTime.to_iso8601(updated_at)

      assert %{
               "id" => ^step_id,
               "initTime" => ^started_at,
               "lastChangeTime" => ^updated_at,
               "processRef" => ^processRef,
               "state" => "Failed"
             } =
               conn
               |> get(~p"/api/projects/#{project.id}/steps/#{step_id}")
               |> json_response(200)
    end

    test "returns 401 on unrelated project", %{conn: conn} do
      other_project = project_fixture()
      %{id: step_id} = insert(:step)

      conn = get(conn, ~p"/api/projects/#{other_project.id}/steps/#{step_id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "returns 401 on invalid token", %{conn: conn, project: project} do
      token =
        Lightning.Tokens.PersonalAccessToken.generate_and_sign!(
          %{"sub" => "user:#{Ecto.UUID.generate()}"},
          Lightning.Config.token_signer()
        )

      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      %{id: step_id} = insert(:step)

      conn = get(conn, ~p"/api/projects/#{project.id}/steps/#{step_id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end
end
