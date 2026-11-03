defmodule LightningWeb.API.RunControllerIndexTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiReadHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp ids(conn),
    do: conn |> json_response(200) |> Map.fetch!("data") |> Enum.map(& &1["id"])

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists the runs of the projects the caller can reach", %{
      conn: conn,
      project: project
    } do
      older =
        insert_run(project,
          state: :started,
          inserted_at: ~U[2024-01-01 10:00:00Z]
        )

      newer =
        insert_run(project,
          state: :success,
          inserted_at: ~U[2024-01-01 12:00:00Z]
        )

      insert_run(insert(:project))

      url = LightningWeb.Endpoint.url()
      page = "#{url}/api/runs?page=1&page_size=10"

      assert conn |> get(~p"/api/runs") |> json_response(200) == %{
               "data" =>
                 for run <- [newer, older] do
                   %{
                     "type" => "runs",
                     "id" => run.id,
                     "relationships" => %{},
                     "links" => %{"self" => "#{url}/api/runs/#{run.id}"},
                     "attributes" => %{
                       "state" => to_string(run.state),
                       "started_at" => nil,
                       "finished_at" => nil,
                       "priority" => "normal",
                       "error_type" => nil
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

    test "lists a superuser's own projects' runs with no project_id", %{
      conn: conn
    } do
      superuser = insert(:user, role: :superuser)
      project = insert(:project, project_users: [%{user_id: superuser.id}])
      run = insert_run(project)
      insert_run(insert(:project))

      assert conn |> assign_bearer(superuser) |> get(~p"/api/runs") |> ids() ==
               [run.id]
    end

    test "narrows by inserted_after", %{conn: conn, project: project} do
      insert_run(project, inserted_at: ~U[2024-01-01 10:00:00Z])
      new = insert_run(project, inserted_at: ~U[2024-01-01 12:00:00Z])

      conn = get(conn, ~p"/api/runs?inserted_after=2024-01-01T11:00:00Z")

      assert ids(conn) == [new.id]
    end

    test "narrows by inserted_before", %{conn: conn, project: project} do
      old = insert_run(project, inserted_at: ~U[2024-01-01 10:00:00Z])
      insert_run(project, inserted_at: ~U[2024-01-01 12:00:00Z])

      conn = get(conn, ~p"/api/runs?inserted_before=2024-01-01T11:00:00Z")

      assert ids(conn) == [old.id]
    end

    test "narrows by project_id", %{conn: conn, user: user} do
      project1 = insert(:project, project_users: [%{user: user, role: :owner}])
      project2 = insert(:project, project_users: [%{user: user, role: :owner}])
      run1 = insert_run(project1)
      insert_run(project2)

      conn = get(conn, ~p"/api/runs?project_id=#{project1.id}")

      assert ids(conn) == [run1.id]
    end

    test "narrows by workflow_id", %{conn: conn, project: project} do
      run1 = insert_run(project)
      insert_run(project)

      conn = get(conn, ~p"/api/runs?workflow_id=#{workflow_of(run1).id}")

      assert ids(conn) == [run1.id]
    end

    test "narrows by work_order_id", %{conn: conn, project: project} do
      run1 = insert_run(project)
      insert_run(project)

      conn = get(conn, ~p"/api/runs?work_order_id=#{run1.work_order_id}")

      assert ids(conn) == [run1.id]
    end

    test "narrows by one state, or by several comma-separated", %{
      conn: conn,
      project: project
    } do
      started = insert_run(project, state: :started)
      failed = insert_run(project, state: :failed)
      insert_run(project, state: :success)

      assert ids(get(conn, ~p"/api/runs?state=started")) == [started.id]

      assert conn
             |> get(~p"/api/runs?state=started,failed")
             |> ids()
             |> Enum.sort() ==
               Enum.sort([started.id, failed.id])
    end

    test "narrows by every filter at once", %{conn: conn, project: project} do
      mid =
        insert_run(project,
          state: :started,
          inserted_at: ~U[2024-01-01 12:00:00Z]
        )

      insert_run(project, state: :started, inserted_at: ~U[2024-01-01 10:00:00Z])

      insert_run(project, state: :started, inserted_at: ~U[2024-01-01 14:00:00Z])

      insert_run(project, state: :failed, inserted_at: ~U[2024-01-01 12:00:00Z])

      conn =
        get(
          conn,
          ~p"/api/runs?inserted_after=2024-01-01T11:00:00Z&inserted_before=2024-01-01T13:00:00Z&state=started"
        )

      assert ids(conn) == [mid.id]
    end

    test "lists one project's runs on the nested route, narrowed by the same filters",
         %{conn: conn, user: user} do
      project1 = insert(:project, project_users: [%{user: user, role: :owner}])
      project2 = insert(:project, project_users: [%{user: user, role: :owner}])
      insert_run(project1, inserted_at: ~U[2024-01-01 10:00:00Z])
      new = insert_run(project1, inserted_at: ~U[2024-01-01 12:00:00Z])
      insert_run(project2, inserted_at: ~U[2024-01-01 12:00:00Z])

      assert conn
             |> get(~p"/api/projects/#{project1.id}/runs")
             |> ids()
             |> length() == 2

      conn =
        get(
          conn,
          ~p"/api/projects/#{project1.id}/runs?inserted_after=2024-01-01T11:00:00Z"
        )

      assert ids(conn) == [new.id]
    end

    test "pages with exact links to the neighbouring pages", %{
      conn: conn,
      project: project
    } do
      for n <- 1..25 do
        insert_run(project,
          inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], n)
        )
      end

      url = "#{LightningWeb.Endpoint.url()}/api/runs"

      assert %{"data" => data, "meta" => meta, "links" => links} =
               conn
               |> get(~p"/api/runs?page=2&page_size=10")
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
            {~p"/api/runs?page_size=1&foo=bar&state=failed,crashed&inserted_after=2024-01-01T02:00:00%2B02:00",
             "/api/runs"},
            {~p"/api/projects/#{project.id}/runs?page_size=1&foo=bar&state=failed,crashed&inserted_after=2024-01-01T02:00:00%2B02:00",
             "/api/projects/#{project.id}/runs"}
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
          "inserted_after" => bad,
          "inserted_before" => bad,
          "updated_after" => bad,
          "updated_before" => bad,
          "workflow_id" => bad,
          "work_order_id" => bad,
          "state" => "started,#{bad}"
        })

      for path <- [
            "/api/runs?" <> query,
            "/api/projects/#{project.id}/runs?" <> query
          ] do
        conn
        |> get(path)
        |> refute_sentinel()
        |> assert_problem(400, :invalid_parameter, [
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
            "parameter" => "work_order_id",
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

  defp workflow_of(run) do
    Lightning.Repo.get!(Lightning.WorkOrder, run.work_order_id)
    |> Lightning.Repo.preload(:workflow)
    |> Map.fetch!(:workflow)
  end
end
