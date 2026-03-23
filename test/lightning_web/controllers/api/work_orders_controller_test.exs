defmodule LightningWeb.API.WorkOrdersControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  # Sample curl requests:
  #
  #   # List all work orders
  #   curl http://localhost:4000/api/work_orders \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # Get a single work order by ID
  #   curl http://localhost:4000/api/work_orders/$WORK_ORDER_ID \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # Filter by comma-separated IDs
  #   curl "http://localhost:4000/api/work_orders?id=$ID1,$ID2" \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # Filter by project, workflow, or date range
  #   curl "http://localhost:4000/api/work_orders?project_id=$PID&inserted_after=2024-01-01T00:00:00Z" \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # Nested route: work orders for a specific project
  #   curl http://localhost:4000/api/projects/$PROJECT_ID/work_orders \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/work_orders")

    assert %{"error" => "Unauthorized"} == json_response(conn, 401)
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/work_orders")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists work orders for projects I have access to", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      # Create a work order in another project (should not be accessible)
      other_project = insert(:project)
      other_workflow = insert(:workflow, project: other_project)
      other_trigger = insert(:trigger, workflow: other_workflow)

      other_workorder =
        insert(:workorder,
          workflow: other_workflow,
          trigger: other_trigger,
          dataclip: build(:dataclip)
        )

      conn = get(conn, ~p"/api/work_orders")

      response = json_response(conn, 200)

      # Should only return work orders from my project
      assert length(response["data"]) == 2

      workorder_ids = Enum.map(response["data"], & &1["id"])
      assert workorder1.id in workorder_ids
      assert workorder2.id in workorder_ids
      refute other_workorder.id in workorder_ids

      # Verify pagination metadata
      assert response["meta"]["total_entries"] == 2
      assert response["meta"]["page_number"] == 1
    end

    test "filters work orders by inserted_after", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      # Create old work order
      _old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time
        )

      # Create new work order
      new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time
        )

      conn = get(conn, ~p"/api/work_orders?inserted_after=2024-01-01T11:00:00Z")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == new_workorder.id
    end

    test "filters work orders by inserted_before", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      # Create old work order
      old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time
        )

      # Create new work order
      _new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time
        )

      conn = get(conn, ~p"/api/work_orders?inserted_before=2024-01-01T11:00:00Z")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == old_workorder.id
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

      # Create work orders at different times
      _old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time
        )

      mid_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: mid_time
        )

      _new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time
        )

      conn =
        get(
          conn,
          ~p"/api/work_orders?inserted_after=2024-01-01T11:00:00Z&inserted_before=2024-01-01T13:00:00Z"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == mid_workorder.id
    end

    test "supports pagination", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      # Create 25 work orders
      Enum.each(1..25, fn i ->
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: DateTime.utc_now() |> DateTime.add(i, :second)
        )
      end)

      # Get first page
      conn = get(conn, ~p"/api/work_orders?page=1&page_size=10")
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

    test "filters work orders by project_id via query parameter", %{
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
          dataclip: build(:dataclip)
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow2,
          trigger: trigger2,
          dataclip: build(:dataclip)
        )

      conn = get(conn, ~p"/api/work_orders?project_id=#{project1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == workorder1.id
      refute Enum.any?(response["data"], fn wo -> wo["id"] == workorder2.id end)
    end

    test "filters work orders by workflow_id via query parameter", %{
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
          dataclip: build(:dataclip)
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow2,
          trigger: trigger2,
          dataclip: build(:dataclip)
        )

      conn = get(conn, ~p"/api/work_orders?workflow_id=#{workflow1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == workorder1.id
      refute Enum.any?(response["data"], fn wo -> wo["id"] == workorder2.id end)
    end

    test "nested route: lists work orders for specific project", %{
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
          dataclip: build(:dataclip)
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow2,
          trigger: trigger2,
          dataclip: build(:dataclip)
        )

      conn = get(conn, ~p"/api/projects/#{project1.id}/work_orders")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == workorder1.id
      refute Enum.any?(response["data"], fn wo -> wo["id"] == workorder2.id end)
    end

    test "nested route: filters work orders by datetime in project scope", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      old_time = ~U[2024-01-01 10:00:00Z]
      new_time = ~U[2024-01-01 12:00:00Z]

      # Create old work order
      _old_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: old_time
        )

      # Create new work order
      new_workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          inserted_at: new_time
        )

      conn =
        get(
          conn,
          ~p"/api/projects/#{project.id}/work_orders?inserted_after=2024-01-01T11:00:00Z"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == new_workorder.id
    end

    test "returns error for invalid inserted_after format", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: build(:dataclip)
      )

      conn =
        get(
          conn,
          ~p"/api/work_orders?inserted_after=not-a-valid-datetime"
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

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: build(:dataclip)
      )

      conn =
        get(
          conn,
          ~p"/api/work_orders?updated_before=2024-13-45"
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

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: build(:dataclip)
      )

      conn = get(conn, ~p"/api/work_orders?inserted_after=123456")

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid datetime format for 'inserted_after'"
      assert error_message =~ "123456"
    end

    test "filters work orders by state", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          state: :pending
        )

      _failed_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          state: :failed
        )

      conn = get(conn, ~p"/api/work_orders?state=pending")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == pending_wo.id
    end

    test "filters work orders by multiple comma-separated states", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          state: :pending
        )

      failed_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          state: :failed
        )

      _success_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip),
          state: :success
        )

      conn = get(conn, ~p"/api/work_orders?state=pending,failed")

      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      ids = Enum.map(response["data"], & &1["id"])
      assert pending_wo.id in ids
      assert failed_wo.id in ids
    end

    test "returns error for invalid state filter", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: build(:dataclip)
      )

      conn = get(conn, ~p"/api/work_orders?state=bogus")

      response = json_response(conn, 400)

      assert %{"error" => error_message} = response
      assert error_message =~ "Invalid state filter"
      assert error_message =~ "bogus"
    end

    test "filters work orders by a single id", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      _workorder2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      conn = get(conn, ~p"/api/work_orders?id=#{workorder1.id}")

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert List.first(response["data"])["id"] == workorder1.id
    end

    test "filters work orders by an array of ids", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      _workorder3 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      conn =
        get(
          conn,
          "/api/work_orders?id[]=#{workorder1.id}&id[]=#{workorder2.id}"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      ids = Enum.map(response["data"], & &1["id"])
      assert workorder1.id in ids
      assert workorder2.id in ids
    end

    test "filters work orders by comma-separated ids", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      workorder2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      _workorder3 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      conn =
        get(
          conn,
          "/api/work_orders?id=#{workorder1.id},#{workorder2.id}"
        )

      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      ids = Enum.map(response["data"], & &1["id"])
      assert workorder1.id in ids
      assert workorder2.id in ids
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "returns a single work order by id", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: build(:dataclip)
        )

      conn = get(conn, ~p"/api/work_orders/#{workorder}")

      response = json_response(conn, 200)

      assert response["data"]["id"] == workorder.id
      assert response["data"]["type"] == "work_orders"
      assert Map.has_key?(response["data"]["attributes"], "state")
      assert Map.has_key?(response["data"]["attributes"], "last_activity")
      assert Map.has_key?(response["data"]["attributes"], "inserted_at")
      assert Map.has_key?(response["data"]["attributes"], "updated_at")
    end

    test "returns 404 for non-existent work order", %{conn: conn} do
      conn = get(conn, ~p"/api/work_orders/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end

    test "returns 401 for work order in project user cannot access", %{
      conn: conn
    } do
      other_project = insert(:project)
      other_workflow = insert(:workflow, project: other_project)
      other_trigger = insert(:trigger, workflow: other_workflow)

      other_workorder =
        insert(:workorder,
          workflow: other_workflow,
          trigger: other_trigger,
          dataclip: build(:dataclip)
        )

      conn = get(conn, ~p"/api/work_orders/#{other_workorder}")

      assert json_response(conn, 401)
    end
  end
end
