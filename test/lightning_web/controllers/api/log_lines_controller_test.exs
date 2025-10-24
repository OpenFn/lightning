defmodule LightningWeb.API.LogLinesControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/log_lines")

    assert %{"error" => "Unauthorized"} == json_response(conn, 401)
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/log_lines")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists log lines for runs in projects I have access to", %{
      conn: conn,
      project: project
    } do
      # Create a workflow and run in my project
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

      run = List.first(workorder.runs)

      # Create log lines for this run
      log1 =
        insert(:log_line,
          run: run,
          message: "First log message",
          level: :info,
          timestamp: DateTime.utc_now()
        )

      log2 =
        insert(:log_line,
          run: run,
          message: "Second log message",
          level: :error,
          timestamp: DateTime.utc_now() |> DateTime.add(1, :second)
        )

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

      other_log =
        insert(:log_line,
          run: other_run,
          message: "Other project log",
          level: :info,
          timestamp: DateTime.utc_now()
        )

      conn = get(conn, ~p"/api/log_lines")

      response = json_response(conn, 200)

      # Should only return logs from my project
      assert length(response["data"]) == 2

      log_ids = Enum.map(response["data"], & &1["id"])
      assert log1.id in log_ids
      assert log2.id in log_ids
      refute other_log.id in log_ids

      # Verify pagination metadata
      assert response["meta"]["total_entries"] == 2
      assert response["meta"]["page_number"] == 1
    end

    test "filters log lines by timestamp_after", %{
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

      run = List.first(workorder.runs)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      _old_log =
        insert(:log_line,
          run: run,
          message: "Old log",
          timestamp: old_time
        )

      new_log =
        insert(:log_line,
          run: run,
          message: "New log",
          timestamp: new_time
        )

      conn =
        get(
          conn,
          ~p"/api/log_lines?timestamp_after=2024-01-01T11:00:00Z"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == new_log.id
    end

    test "filters log lines by timestamp_before", %{
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

      run = List.first(workorder.runs)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      old_log =
        insert(:log_line,
          run: run,
          message: "Old log",
          timestamp: old_time
        )

      _new_log =
        insert(:log_line,
          run: run,
          message: "New log",
          timestamp: new_time
        )

      conn =
        get(
          conn,
          ~p"/api/log_lines?timestamp_before=2024-01-01T11:00:00Z"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == old_log.id
    end

    test "filters log lines by level", %{
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

      run = List.first(workorder.runs)

      _info_log =
        insert(:log_line,
          run: run,
          message: "Info message",
          level: :info,
          timestamp: DateTime.utc_now()
        )

      error_log =
        insert(:log_line,
          run: run,
          message: "Error message",
          level: :error,
          timestamp: DateTime.utc_now()
        )

      conn = get(conn, ~p"/api/log_lines?level=error")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == error_log.id
      assert List.first(response["data"])["attributes"]["level"] == "error"
    end

    test "filters log lines by run_id", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      # Create two runs
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

      log1 = insert(:log_line, run: run1, message: "Run 1 log")
      _log2 = insert(:log_line, run: run2, message: "Run 2 log")

      conn = get(conn, ~p"/api/log_lines?run_id=#{run1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == log1.id
    end

    test "filters log lines by work_order_id", %{
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

      log1 = insert(:log_line, run: run1, message: "WorkOrder 1 log")
      _log2 = insert(:log_line, run: run2, message: "WorkOrder 2 log")

      conn = get(conn, ~p"/api/log_lines?work_order_id=#{workorder1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == log1.id
    end

    test "filters log lines by workflow_id", %{
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

      log1 = insert(:log_line, run: run1, message: "Workflow 1 log")
      _log2 = insert(:log_line, run: run2, message: "Workflow 2 log")

      conn = get(conn, ~p"/api/log_lines?workflow_id=#{workflow1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == log1.id
    end

    test "filters log lines by project_id", %{
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

      log1 = insert(:log_line, run: run1, message: "Project 1 log")
      _log2 = insert(:log_line, run: run2, message: "Project 2 log")

      conn = get(conn, ~p"/api/log_lines?project_id=#{project1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == log1.id
    end

    test "combines multiple filters", %{
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

      run = List.first(workorder.runs)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      # Should match filters
      _match_log =
        insert(:log_line,
          run: run,
          message: "Match",
          level: :error,
          timestamp: new_time
        )

      # Wrong level
      _wrong_level =
        insert(:log_line,
          run: run,
          message: "Wrong level",
          level: :info,
          timestamp: new_time
        )

      # Wrong time
      _wrong_time =
        insert(:log_line,
          run: run,
          message: "Wrong time",
          level: :error,
          timestamp: old_time
        )

      conn =
        get(
          conn,
          ~p"/api/log_lines?level=error&timestamp_after=2024-01-01T11:00:00Z"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["attributes"]["message"] == "Match"
    end

    test "supports pagination", %{
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

      run = List.first(workorder.runs)

      # Create 25 log lines
      Enum.each(1..25, fn i ->
        insert(:log_line,
          run: run,
          message: "Log #{i}",
          timestamp: DateTime.utc_now() |> DateTime.add(i, :second)
        )
      end)

      # Get first page
      conn = get(conn, ~p"/api/log_lines?page=1&page_size=10")
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

    test "returns logs ordered by timestamp desc (newest first)", %{
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

      run = List.first(workorder.runs)

      _log1 =
        insert(:log_line,
          run: run,
          message: "First",
          timestamp: ~U[2024-01-01 10:00:00Z]
        )

      log2 =
        insert(:log_line,
          run: run,
          message: "Second",
          timestamp: ~U[2024-01-01 11:00:00Z]
        )

      _log3 =
        insert(:log_line,
          run: run,
          message: "Third",
          timestamp: ~U[2024-01-01 12:00:00Z]
        )

      conn = get(conn, ~p"/api/log_lines?page_size=1")
      response = json_response(conn, 200)

      # Should get the newest log first
      assert List.first(response["data"])["attributes"]["message"] == "Third"

      # Get second page
      conn = get(conn, ~p"/api/log_lines?page=2&page_size=1")
      response = json_response(conn, 200)

      assert List.first(response["data"])["id"] == log2.id
    end

    test "returns error for invalid timestamp_after format", %{
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

      run = List.first(workorder.runs)

      insert(:log_line,
        run: run,
        message: "Test log",
        timestamp: DateTime.utc_now()
      )

      conn =
        get(
          conn,
          ~p"/api/log_lines?timestamp_after=not-a-valid-datetime"
        )

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid datetime format for 'timestamp_after'"
      assert error_message =~ "not-a-valid-datetime"
    end

    test "returns error for invalid timestamp_before format", %{
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

      run = List.first(workorder.runs)

      insert(:log_line,
        run: run,
        message: "Test log",
        timestamp: DateTime.utc_now()
      )

      conn =
        get(
          conn,
          ~p"/api/log_lines?timestamp_before=2024-13-45"
        )

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid datetime format for 'timestamp_before'"
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

      run = List.first(workorder.runs)

      insert(:log_line,
        run: run,
        message: "Test log",
        timestamp: DateTime.utc_now()
      )

      conn = get(conn, ~p"/api/log_lines?timestamp_after=123456")

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid datetime format for 'timestamp_after'"
      assert error_message =~ "123456"
    end
  end
end
