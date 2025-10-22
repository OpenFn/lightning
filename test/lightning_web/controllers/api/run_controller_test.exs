defmodule LightningWeb.API.RunControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/runs")

    assert %{"error" => "Unauthorized"} == json_response(conn, 401)
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/runs")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists runs for projects I have access to", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger
            }
          ]
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :success,
              dataclip: build(:dataclip),
              starting_trigger: trigger
            }
          ]
        )

      run1 = List.first(workorder1.runs)
      run2 = List.first(workorder2.runs)

      # Create a run in another project (should not be accessible)
      other_project = insert(:project)
      other_workflow = insert(:workflow, project: other_project)
      other_trigger = insert(:trigger, workflow: other_workflow)

      other_workorder =
        insert(:workorder,
          workflow: other_workflow,
          trigger: other_trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: other_trigger
            }
          ]
        )

      other_run = List.first(other_workorder.runs)

      conn = get(conn, ~p"/api/runs")

      response = json_response(conn, 200)

      # Should only return runs from my project
      assert length(response["data"]) == 2

      run_ids = Enum.map(response["data"], & &1["id"])
      assert run1.id in run_ids
      assert run2.id in run_ids
      refute other_run.id in run_ids

      # Verify pagination metadata
      assert response["meta"]["total_entries"] == 2
      assert response["meta"]["page_number"] == 1
    end

    test "filters runs by inserted_after", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      # Create old run
      _old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: old_time
            }
          ]
        )

      # Create new run
      new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: new_time
            }
          ]
        )

      new_run = List.first(new_workorder.runs)

      conn = get(conn, ~p"/api/runs?inserted_after=2024-01-01T11:00:00Z")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == new_run.id
    end

    test "filters runs by inserted_before", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      # Create old run
      old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: old_time
            }
          ]
        )

      # Create new run
      _new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: new_time
            }
          ]
        )

      old_run = List.first(old_workorder.runs)

      conn = get(conn, ~p"/api/runs?inserted_before=2024-01-01T11:00:00Z")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == old_run.id
    end

    test "combines multiple filters", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      old_time = ~U[2024-01-01 10:00:00Z]
      mid_time = ~U[2024-01-01 12:00:00Z]
      new_time = ~U[2024-01-01 14:00:00Z]

      # Create runs at different times
      _old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: old_time
            }
          ]
        )

      mid_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: mid_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: mid_time
            }
          ]
        )

      _new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: new_time
            }
          ]
        )

      mid_run = List.first(mid_workorder.runs)

      conn =
        get(
          conn,
          ~p"/api/runs?inserted_after=2024-01-01T11:00:00Z&inserted_before=2024-01-01T13:00:00Z"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == mid_run.id
    end

    test "supports pagination", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      # Create 25 runs
      Enum.each(1..25, fn i ->
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: DateTime.utc_now() |> DateTime.add(i, :second),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: DateTime.utc_now() |> DateTime.add(i, :second)
            }
          ]
        )
      end)

      # Get first page
      conn = get(conn, ~p"/api/runs?page=1&page_size=10")
      response = json_response(conn, 200)

      assert length(response["data"]) == 10
      assert response["meta"]["total_entries"] == 25
      assert response["meta"]["total_pages"] == 3
      assert response["meta"]["page_number"] == 1
      assert response["meta"]["page_size"] == 10

      # Verify pagination links exist
      assert Map.has_key?(response["links"], "first")
      assert Map.has_key?(response["links"], "next")
      assert Map.has_key?(response["links"], "last")
    end

    test "filters runs by project_id via query parameter", %{
      conn: conn,
      user: user
    } do
      # User has access to both projects
      project1 = insert(:project, project_users: [%{user: user, role: :owner}])
      project2 = insert(:project, project_users: [%{user: user, role: :owner}])

      workflow1 = insert(:workflow, project: project1)
      workflow2 = insert(:workflow, project: project2)
      trigger1 = insert(:trigger, workflow: workflow1)
      trigger2 = insert(:trigger, workflow: workflow2)

      workorder1 =
        insert(:workorder,
          workflow: workflow1,
          trigger: trigger1,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger1
            }
          ]
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow2,
          trigger: trigger2,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger2
            }
          ]
        )

      run1 = List.first(workorder1.runs)
      run2 = List.first(workorder2.runs)

      conn = get(conn, ~p"/api/runs?project_id=#{project1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == run1.id
      refute Enum.any?(response["data"], fn r -> r["id"] == run2.id end)
    end

    test "filters runs by workflow_id via query parameter", %{
      conn: conn,
      project: project
    } do
      workflow1 = insert(:workflow, project: project)
      workflow2 = insert(:workflow, project: project)
      trigger1 = insert(:trigger, workflow: workflow1)
      trigger2 = insert(:trigger, workflow: workflow2)

      workorder1 =
        insert(:workorder,
          workflow: workflow1,
          trigger: trigger1,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger1
            }
          ]
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow2,
          trigger: trigger2,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger2
            }
          ]
        )

      run1 = List.first(workorder1.runs)
      run2 = List.first(workorder2.runs)

      conn = get(conn, ~p"/api/runs?workflow_id=#{workflow1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == run1.id
      refute Enum.any?(response["data"], fn r -> r["id"] == run2.id end)
    end

    test "filters runs by work_order_id via query parameter", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger
            }
          ]
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger
            }
          ]
        )

      run1 = List.first(workorder1.runs)
      run2 = List.first(workorder2.runs)

      conn = get(conn, ~p"/api/runs?work_order_id=#{workorder1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == run1.id
      refute Enum.any?(response["data"], fn r -> r["id"] == run2.id end)
    end

    test "nested route: lists runs for specific project", %{
      conn: conn,
      user: user
    } do
      # User has access to both projects
      project1 = insert(:project, project_users: [%{user: user, role: :owner}])
      project2 = insert(:project, project_users: [%{user: user, role: :owner}])

      workflow1 = insert(:workflow, project: project1)
      workflow2 = insert(:workflow, project: project2)
      trigger1 = insert(:trigger, workflow: workflow1)
      trigger2 = insert(:trigger, workflow: workflow2)

      workorder1 =
        insert(:workorder,
          workflow: workflow1,
          trigger: trigger1,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger1
            }
          ]
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow2,
          trigger: trigger2,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger2
            }
          ]
        )

      run1 = List.first(workorder1.runs)
      run2 = List.first(workorder2.runs)

      conn = get(conn, ~p"/api/projects/#{project1.id}/runs")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == run1.id
      refute Enum.any?(response["data"], fn r -> r["id"] == run2.id end)
    end

    test "nested route: filters runs by datetime in project scope", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      # Create old run
      _old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: old_time
            }
          ]
        )

      # Create new run
      new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time,
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger,
              inserted_at: new_time
            }
          ]
        )

      new_run = List.first(new_workorder.runs)

      conn =
        get(
          conn,
          ~p"/api/projects/#{project.id}/runs?inserted_after=2024-01-01T11:00:00Z"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == new_run.id
    end

    test "returns error for invalid inserted_after format", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger
            }
          ]
        )

      _run = List.first(workorder.runs)

      conn =
        get(
          conn,
          ~p"/api/runs?inserted_after=not-a-valid-datetime"
        )

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid datetime format for 'inserted_after'"
      assert error_message =~ "not-a-valid-datetime"
    end

    test "returns error for invalid updated_before format", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger
            }
          ]
        )

      _run = List.first(workorder.runs)

      conn =
        get(
          conn,
          ~p"/api/runs?updated_before=2024-13-45"
        )

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid datetime format for 'updated_before'"
      assert error_message =~ "2024-13-45"
    end

    test "returns error for invalid datetime with integer", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            %{
              state: :started,
              dataclip: build(:dataclip),
              starting_trigger: trigger
            }
          ]
        )

      _run = List.first(workorder.runs)

      conn = get(conn, ~p"/api/runs?inserted_after=123456")

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid datetime format for 'inserted_after'"
      assert error_message =~ "123456"
    end
  end
end
