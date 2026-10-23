defmodule LightningWeb.API.WorkOrdersControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiReadHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp ids(conn) do
    conn |> json_response(200) |> Map.fetch!("data") |> Enum.map(& &1["id"])
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists the work orders of the projects the caller can reach", %{
      conn: conn,
      project: project
    } do
      older =
        insert_work_order(project,
          state: :failed,
          inserted_at: ~U[2024-01-01 10:00:00.000000Z],
          updated_at: ~U[2024-01-01 10:30:00.000000Z],
          last_activity: ~U[2024-01-01 10:20:00.000000Z]
        )

      newer =
        insert_work_order(project,
          state: :success,
          inserted_at: ~U[2024-01-01 12:00:00.000000Z],
          updated_at: ~U[2024-01-01 12:30:00.000000Z],
          last_activity: ~U[2024-01-01 12:20:00.000000Z]
        )

      insert_work_order(insert(:project))

      url = LightningWeb.Endpoint.url()
      page = "#{url}/api/work_orders?page=1&page_size=10"

      assert conn |> get(~p"/api/work_orders") |> json_response(200) == %{
               "data" =>
                 for {work_order, state, last_activity, inserted_at, updated_at} <-
                       [
                         {newer, "success", "2024-01-01T12:20:00.000000Z",
                          "2024-01-01T12:00:00.000000Z",
                          "2024-01-01T12:30:00.000000Z"},
                         {older, "failed", "2024-01-01T10:20:00.000000Z",
                          "2024-01-01T10:00:00.000000Z",
                          "2024-01-01T10:30:00.000000Z"}
                       ] do
                   %{
                     "type" => "work_orders",
                     "id" => work_order.id,
                     "relationships" => %{},
                     "links" => %{
                       "self" => "#{url}/api/work_orders/#{work_order.id}"
                     },
                     "attributes" => %{
                       "state" => state,
                       "last_activity" => last_activity,
                       "inserted_at" => inserted_at,
                       "updated_at" => updated_at
                     }
                   }
                 end,
               "included" => [],
               "meta" => %{
                 "total_entries" => 2,
                 "total_pages" => 1,
                 "page_number" => 1,
                 "page_size" => 10
               },
               "links" => %{
                 "self" => page,
                 "first" => page,
                 "last" => page,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "narrows by inserted_after", %{conn: conn, project: project} do
      insert_work_order(project, inserted_at: ~U[2024-01-01 10:00:00Z])
      new = insert_work_order(project, inserted_at: ~U[2024-01-01 12:00:00Z])

      conn = get(conn, ~p"/api/work_orders?inserted_after=2024-01-01T11:00:00Z")

      assert ids(conn) == [new.id]
    end

    test "narrows by inserted_before", %{conn: conn, project: project} do
      old = insert_work_order(project, inserted_at: ~U[2024-01-01 10:00:00Z])
      insert_work_order(project, inserted_at: ~U[2024-01-01 12:00:00Z])

      conn = get(conn, ~p"/api/work_orders?inserted_before=2024-01-01T11:00:00Z")

      assert ids(conn) == [old.id]
    end

    test "narrows by project_id", %{conn: conn, user: user} do
      project1 = insert(:project, project_users: [%{user: user, role: :owner}])
      project2 = insert(:project, project_users: [%{user: user, role: :owner}])
      work_order1 = insert_work_order(project1)
      insert_work_order(project2)

      conn = get(conn, ~p"/api/work_orders?project_id=#{project1.id}")

      assert ids(conn) == [work_order1.id]
    end

    test "narrows by workflow_id", %{conn: conn, project: project} do
      work_order1 = insert_work_order(project)
      insert_work_order(project)

      conn =
        get(conn, ~p"/api/work_orders?workflow_id=#{work_order1.workflow_id}")

      assert ids(conn) == [work_order1.id]
    end

    test "narrows by one state, or by several comma-separated", %{
      conn: conn,
      project: project
    } do
      pending = insert_work_order(project, state: :pending)
      failed = insert_work_order(project, state: :failed)
      insert_work_order(project, state: :success)

      assert ids(get(conn, ~p"/api/work_orders?state=pending")) == [pending.id]

      assert conn
             |> get(~p"/api/work_orders?state=pending,failed")
             |> ids()
             |> Enum.sort() == Enum.sort([pending.id, failed.id])
    end

    test "filters work orders by a single id", %{conn: conn, project: project} do
      work_order1 = insert_work_order(project)
      insert_work_order(project)

      conn = get(conn, ~p"/api/work_orders?id=#{work_order1.id}")

      assert ids(conn) == [work_order1.id]
    end

    test "filters work orders by an array of ids", %{
      conn: conn,
      project: project
    } do
      work_order1 = insert_work_order(project)
      work_order2 = insert_work_order(project)
      insert_work_order(project)

      conn =
        get(
          conn,
          "/api/work_orders?id[]=#{work_order1.id}&id[]=#{work_order2.id}"
        )

      assert Enum.sort(ids(conn)) == Enum.sort([work_order1.id, work_order2.id])
    end

    test "filters work orders by comma-separated ids", %{
      conn: conn,
      project: project
    } do
      work_order1 = insert_work_order(project)
      work_order2 = insert_work_order(project)
      insert_work_order(project)

      conn =
        get(conn, "/api/work_orders?id=#{work_order1.id},#{work_order2.id}")

      assert Enum.sort(ids(conn)) == Enum.sort([work_order1.id, work_order2.id])
    end

    test "narrows by every filter at once", %{conn: conn, project: project} do
      mid =
        insert_work_order(project,
          state: :failed,
          inserted_at: ~U[2024-01-01 12:00:00Z]
        )

      insert_work_order(project,
        state: :failed,
        inserted_at: ~U[2024-01-01 10:00:00Z]
      )

      insert_work_order(project,
        state: :failed,
        inserted_at: ~U[2024-01-01 14:00:00Z]
      )

      insert_work_order(project,
        state: :pending,
        inserted_at: ~U[2024-01-01 12:00:00Z]
      )

      conn =
        get(
          conn,
          ~p"/api/work_orders?inserted_after=2024-01-01T11:00:00Z&inserted_before=2024-01-01T13:00:00Z&state=failed"
        )

      assert ids(conn) == [mid.id]
    end

    test "lists one project's work orders on the nested route, narrowed by the same filters",
         %{conn: conn, user: user} do
      project1 = insert(:project, project_users: [%{user: user, role: :owner}])
      project2 = insert(:project, project_users: [%{user: user, role: :owner}])
      insert_work_order(project1, inserted_at: ~U[2024-01-01 10:00:00Z])
      new = insert_work_order(project1, inserted_at: ~U[2024-01-01 12:00:00Z])
      insert_work_order(project2, inserted_at: ~U[2024-01-01 12:00:00Z])

      assert conn
             |> get(~p"/api/projects/#{project1.id}/work_orders")
             |> ids()
             |> length() == 2

      conn =
        get(
          conn,
          ~p"/api/projects/#{project1.id}/work_orders?inserted_after=2024-01-01T11:00:00Z"
        )

      assert ids(conn) == [new.id]
    end

    test "pages with exact links to the neighbouring pages", %{
      conn: conn,
      project: project
    } do
      for n <- 1..25 do
        insert_work_order(project,
          inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], n)
        )
      end

      url = "#{LightningWeb.Endpoint.url()}/api/work_orders"

      assert %{"data" => data, "meta" => meta, "links" => links} =
               conn
               |> get(~p"/api/work_orders?page=2&page_size=10")
               |> json_response(200)

      assert length(data) == 10

      assert meta == %{
               "total_entries" => 25,
               "total_pages" => 3,
               "page_number" => 2,
               "page_size" => 10
             }

      assert links == %{
               "self" => "#{url}?page=2&page_size=10",
               "first" => "#{url}?page=1&page_size=10",
               "last" => "#{url}?page=3&page_size=10",
               "next" => "#{url}?page=3&page_size=10",
               "prev" => "#{url}?page=1&page_size=10"
             }
    end

    test "pagination links carry the filters applied and nothing else", %{
      conn: conn,
      project: project
    } do
      for {path, request_path} <- [
            {~p"/api/work_orders?page_size=1&foo=bar&state=failed,crashed&inserted_after=2024-01-01T02:00:00%2B02:00",
             "/api/work_orders"},
            {~p"/api/projects/#{project.id}/work_orders?page_size=1&foo=bar&state=failed,crashed&inserted_after=2024-01-01T02:00:00%2B02:00",
             "/api/projects/#{project.id}/work_orders"}
          ] do
        %{"links" => links} = conn |> get(path) |> json_response(200)

        for key <- ["self", "first"] do
          uri = URI.parse(links[key])
          assert uri.path == request_path

          assert URI.decode_query(uri.query) == %{
                   "inserted_after" => "2024-01-01T00:00:00.000000Z",
                   "page" => "1",
                   "page_size" => "1",
                   "state" => "failed,crashed"
                 }
        end
      end
    end

    test "every bad query parameter is reported, none quoted", %{
      conn: conn,
      project: project
    } do
      bad = plant_sentinel(%{"v" => "x"})["v"]

      query =
        URI.encode_query(%{
          "id" => bad,
          "inserted_after" => bad,
          "inserted_before" => bad,
          "updated_after" => bad,
          "updated_before" => bad,
          "workflow_id" => bad,
          "state" => "pending,#{bad}"
        })

      for path <- [
            "/api/work_orders?" <> query,
            "/api/projects/#{project.id}/work_orders?" <> query
          ] do
        conn
        |> get(path)
        |> refute_sentinel()
        |> assert_problem(400, :invalid_parameter, [
          %{"parameter" => "id", "code" => "type", "detail" => "is invalid"},
          %{
            "parameter" => "inserted_after",
            "code" => "type",
            "detail" => "is invalid"
          },
          %{
            "parameter" => "inserted_before",
            "code" => "type",
            "detail" => "is invalid"
          },
          %{
            "parameter" => "updated_after",
            "code" => "type",
            "detail" => "is invalid"
          },
          %{
            "parameter" => "updated_before",
            "code" => "type",
            "detail" => "is invalid"
          },
          %{
            "parameter" => "workflow_id",
            "code" => "type",
            "detail" => "is invalid"
          },
          %{
            "parameter" => "state",
            "code" => "not_allowed",
            "detail" => "has an invalid entry"
          }
        ])
      end
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "answers the work order, and links to it without the request's query",
         %{conn: conn, project: project} do
      work_order =
        insert_work_order(project,
          state: :success,
          last_activity: ~U[2024-01-01 11:00:00.000000Z],
          inserted_at: ~U[2024-01-01 10:00:00.000000Z],
          updated_at: ~U[2024-01-01 12:00:00.000000Z]
        )

      url = LightningWeb.Endpoint.url()

      assert conn
             |> get(~p"/api/work_orders/#{work_order}?foo=bar")
             |> json_response(200) == %{
               "data" => %{
                 "type" => "work_orders",
                 "id" => work_order.id,
                 "relationships" => %{},
                 "links" => %{
                   "self" => "#{url}/api/work_orders/#{work_order.id}"
                 },
                 "attributes" => %{
                   "state" => "success",
                   "last_activity" => "2024-01-01T11:00:00.000000Z",
                   "inserted_at" => "2024-01-01T10:00:00.000000Z",
                   "updated_at" => "2024-01-01T12:00:00.000000Z"
                 }
               },
               "included" => [],
               "links" => %{"self" => "#{url}/api/work_orders/#{work_order.id}"}
             }
    end
  end

  describe "who may reach it" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "answers 404 for what the caller has no standing on or that is missing, before the query is read, and 403 to a member who has not met the MFA requirement",
         %{conn: conn, project: project} do
      own = insert_work_order(project)
      elsewhere = insert(:project)
      unseen = insert_work_order(elsewhere)
      Lightning.Repo.update!(Ecto.Changeset.change(project, requires_mfa: true))

      for {path, status, code} <- [
            {~p"/api/projects/#{elsewhere.id}/work_orders?state=sideways", 404,
             :not_found},
            {~p"/api/projects/#{Ecto.UUID.generate()}/work_orders", 404,
             :not_found},
            {~p"/api/work_orders/#{unseen.id}", 404, :not_found},
            {~p"/api/work_orders/#{Ecto.UUID.generate()}", 404, :not_found},
            {~p"/api/work_orders/#{own.id}", 403, :forbidden}
          ] do
        conn |> get(path) |> assert_problem(status, code, [])
      end
    end
  end
end
