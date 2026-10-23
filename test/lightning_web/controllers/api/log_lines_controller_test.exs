defmodule LightningWeb.API.LogLinesControllerTest do
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

  defp insert_log_line(run, attrs \\ []) do
    insert(
      :log_line,
      [run: run, timestamp: ~U[2024-01-01 10:00:00.000000Z]] ++ attrs
    )
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists the log lines of the projects the caller can reach, newest first",
         %{conn: conn, project: project} do
      run = insert_run(project)

      older =
        insert_log_line(run,
          message: "First log message",
          level: :info,
          timestamp: ~U[2024-01-01 10:00:00.000000Z]
        )

      newer =
        insert_log_line(run,
          message: "Second log message",
          level: :error,
          timestamp: ~U[2024-01-01 11:00:00.000000Z]
        )

      insert_log_line(insert_run(insert(:project)))

      page = "#{LightningWeb.Endpoint.url()}/api/log_lines?page=1&page_size=10"

      assert conn |> get(~p"/api/log_lines") |> json_response(200) == %{
               "data" => [
                 %{
                   "type" => "log_lines",
                   "id" => newer.id,
                   "attributes" => %{
                     "source" => nil,
                     "level" => "error",
                     "message" => "Second log message",
                     "timestamp" => "2024-01-01T11:00:00.000000Z",
                     "step_id" => nil,
                     "run_id" => run.id
                   }
                 },
                 %{
                   "type" => "log_lines",
                   "id" => older.id,
                   "attributes" => %{
                     "source" => nil,
                     "level" => "info",
                     "message" => "First log message",
                     "timestamp" => "2024-01-01T10:00:00.000000Z",
                     "step_id" => nil,
                     "run_id" => run.id
                   }
                 }
               ],
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

    test "narrows by timestamp_after", %{conn: conn, project: project} do
      run = insert_run(project)
      insert_log_line(run, timestamp: ~U[2024-01-01 10:00:00.000000Z])
      new = insert_log_line(run, timestamp: ~U[2024-01-01 12:00:00.000000Z])

      conn = get(conn, ~p"/api/log_lines?timestamp_after=2024-01-01T11:00:00Z")

      assert ids(conn) == [new.id]
    end

    test "narrows by timestamp_before", %{conn: conn, project: project} do
      run = insert_run(project)
      old = insert_log_line(run, timestamp: ~U[2024-01-01 10:00:00.000000Z])
      insert_log_line(run, timestamp: ~U[2024-01-01 12:00:00.000000Z])

      conn = get(conn, ~p"/api/log_lines?timestamp_before=2024-01-01T11:00:00Z")

      assert ids(conn) == [old.id]
    end

    test "narrows by level", %{conn: conn, project: project} do
      run = insert_run(project)
      insert_log_line(run, level: :info)
      error = insert_log_line(run, level: :error)

      assert ids(get(conn, ~p"/api/log_lines?level=error")) == [error.id]
    end

    test "narrows by run_id", %{conn: conn, project: project} do
      run1 = insert_run(project)
      log1 = insert_log_line(run1)
      insert_log_line(insert_run(project))

      assert ids(get(conn, ~p"/api/log_lines?run_id=#{run1.id}")) == [log1.id]
    end

    test "narrows by work_order_id", %{conn: conn, project: project} do
      run1 = insert_run(project)
      log1 = insert_log_line(run1)
      insert_log_line(insert_run(project))

      conn = get(conn, ~p"/api/log_lines?work_order_id=#{run1.work_order_id}")

      assert ids(conn) == [log1.id]
    end

    test "narrows by workflow_id", %{conn: conn, project: project} do
      workflow1 = insert(:workflow, project: project)
      log1 = workflow1 |> insert_run() |> insert_log_line()
      insert_log_line(insert_run(project))

      assert ids(get(conn, ~p"/api/log_lines?workflow_id=#{workflow1.id}")) ==
               [log1.id]
    end

    test "narrows by project_id", %{conn: conn, user: user} do
      project1 = insert(:project, project_users: [%{user: user, role: :owner}])
      project2 = insert(:project, project_users: [%{user: user, role: :owner}])
      log1 = project1 |> insert_run() |> insert_log_line()
      insert_log_line(insert_run(project2))

      assert ids(get(conn, ~p"/api/log_lines?project_id=#{project1.id}")) ==
               [log1.id]
    end

    test "narrows by every filter at once", %{conn: conn, project: project} do
      run = insert_run(project)

      match =
        insert_log_line(run,
          level: :error,
          timestamp: ~U[2024-01-01 12:00:00.000000Z]
        )

      insert_log_line(run,
        level: :info,
        timestamp: ~U[2024-01-01 12:00:00.000000Z]
      )

      insert_log_line(run,
        level: :error,
        timestamp: ~U[2024-01-01 10:00:00.000000Z]
      )

      conn =
        get(
          conn,
          ~p"/api/log_lines?level=error&timestamp_after=2024-01-01T11:00:00Z"
        )

      assert ids(conn) == [match.id]
    end

    test "pages with exact links to the neighbouring pages", %{
      conn: conn,
      project: project
    } do
      run = insert_run(project)

      for n <- 1..25 do
        insert_log_line(run,
          timestamp: DateTime.add(~U[2024-01-01 00:00:00Z], n)
        )
      end

      url = "#{LightningWeb.Endpoint.url()}/api/log_lines"

      assert %{"data" => data, "meta" => meta, "links" => links} =
               conn
               |> get(~p"/api/log_lines?page=2&page_size=10")
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

    test "returns logs ordered by timestamp desc (newest first)", %{
      conn: conn,
      project: project
    } do
      run = insert_run(project)
      insert_log_line(run, message: "First", timestamp: ~U[2024-01-01 10:00:00Z])

      log2 =
        insert_log_line(run,
          message: "Second",
          timestamp: ~U[2024-01-01 11:00:00Z]
        )

      insert_log_line(run, message: "Third", timestamp: ~U[2024-01-01 12:00:00Z])

      conn = get(conn, ~p"/api/log_lines?page_size=1")
      response = json_response(conn, 200)

      assert List.first(response["data"])["attributes"]["message"] == "Third"

      conn = get(conn, ~p"/api/log_lines?page=2&page_size=1")
      response = json_response(conn, 200)

      assert List.first(response["data"])["id"] == log2.id
    end

    test "pagination links carry the filters applied and nothing else", %{
      conn: conn,
      project: project
    } do
      run = insert_run(project)
      insert_log_line(run, level: :error)
      insert_log_line(run, level: :error)

      %{"links" => links} =
        conn
        |> get(
          ~p"/api/log_lines?page_size=1&foo=bar&level=error&timestamp_after=2024-01-01T02:00:00%2B02:00"
        )
        |> json_response(200)

      uri = URI.parse(links["next"])
      assert uri.path == "/api/log_lines"

      assert URI.decode_query(uri.query) == %{
               "level" => "error",
               "timestamp_after" => "2024-01-01T00:00:00.000000Z",
               "page" => "2",
               "page_size" => "1"
             }

      self_uri = URI.parse(links["self"])
      assert self_uri.path == "/api/log_lines"

      assert URI.decode_query(self_uri.query) == %{
               "level" => "error",
               "timestamp_after" => "2024-01-01T00:00:00.000000Z",
               "page" => "1",
               "page_size" => "1"
             }
    end

    test "every bad query parameter is reported, none quoted", %{conn: conn} do
      bad = plant_sentinel(%{"v" => "x"})["v"]

      query =
        URI.encode_query(%{
          "timestamp_after" => bad,
          "timestamp_before" => bad,
          "level" => bad,
          "run_id" => bad,
          "job_id" => bad,
          "workflow_id" => bad,
          "work_order_id" => bad
        })

      conn
      |> get("/api/log_lines?" <> query)
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "timestamp_after",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "parameter" => "timestamp_before",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "parameter" => "level",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        %{"parameter" => "run_id", "code" => "type", "detail" => "is invalid"},
        %{"parameter" => "job_id", "code" => "type", "detail" => "is invalid"},
        %{
          "parameter" => "workflow_id",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "parameter" => "work_order_id",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])
    end
  end

  describe "who may reach it" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "filtering by a project the caller has no standing on lists nothing",
         %{conn: conn} do
      elsewhere = insert(:project)
      insert_log_line(insert_run(elsewhere), level: :error)

      assert %{"data" => []} =
               conn
               |> get(~p"/api/log_lines?#{%{project_id: elsewhere.id}}")
               |> json_response(200)
    end
  end
end
