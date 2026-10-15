defmodule LightningWeb.API.ProblemTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers

  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem

  defp respond(accept, problem) do
    build_conn()
    |> then(fn conn ->
      if accept, do: put_req_header(conn, "accept", accept), else: conn
    end)
    |> Phoenix.Controller.accepts(["json"])
    |> Problem.respond(problem)
  end

  describe "respond/2" do
    test "sends one body, as application/problem+json only when Accept names it, and never refuses it with a 406" do
      answers =
        for {accept, content_type} <- [
              {nil, "application/json"},
              {"*/*", "application/json"},
              {"application/json", "application/json"},
              {"application/problem+json", "application/problem+json"},
              {"application/json, application/problem+json;q=0.5",
               "application/problem+json"}
            ] do
          conn = respond(accept, Problem.new(:not_found))

          assert get_resp_header(conn, "content-type") == [
                   "#{content_type}; charset=utf-8"
                 ]

          assert_problem(conn, 404, :not_found, [])
        end

      assert Enum.uniq(answers) == [
               %{
                 "type" => "about:blank",
                 "status" => 404,
                 "title" => "Not Found",
                 "code" => "not_found",
                 "detail" => "Not found, or you don't have access to it."
               }
             ]
    end

    test "an API route takes a request that accepts only application/problem+json" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/problem+json")
        |> get(~p"/api/projects")

      assert conn.status == 401
    end

    test "sends the problem's entries, extensions and headers" do
      problem =
        Problem.new(:not_ready,
          headers: [{"retry-after", "5"}],
          extensions: %{work_order_id: "wo-1"}
        )

      conn = respond(nil, problem)

      assert get_resp_header(conn, "retry-after") == ["5"]
      assert %{"work_order_id" => "wo-1"} = assert_problem(conn, 503, :not_ready)
    end
  end

  describe "FallbackController" do
    test "answers each result it takes with one status and code" do
      for {result, status, code} <- [
            {{:error, :not_found}, 404, :not_found},
            {{:error, :no_such_project}, 404, :not_found},
            {{:error, :connection_not_for_this_project}, 404, :not_found},
            {{:error, :forbidden}, 403, :forbidden},
            {{:error, :insufficient_scope}, 403, :insufficient_scope},
            {{:error, :scheduled_for_deletion}, 409, :scheduled_for_deletion},
            {{:error, :id_taken}, 409, :id_taken},
            {{:error, :exceeds_limit}, 402, :exceeds_limit},
            {{:error, Problem.new(:being_edited)}, 409, :being_edited}
          ] do
        build_conn()
        |> FallbackController.call(result)
        |> assert_problem(status, code, [])
      end
    end

    test "answers a refused changeset by its errors" do
      changeset =
        Lightning.Projects.Project.project_with_users_changeset(
          %Lightning.Projects.Project{},
          %{"project_users" => []}
        )

      build_conn()
      |> FallbackController.call({:error, changeset})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/project_users",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/owner",
          "code" => "one_owner",
          "detail" =>
            "Every project must have exactly one owner. Please specify one below."
        }
      ])
    end

    test "logs a snapshot that failed to save, and answers 500" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          build_conn()
          |> FallbackController.call({:error, :snapshot_failed})
          |> assert_problem(500, :internal, [])
        end)

      assert log =~ "could not save a workflow snapshot"
    end

    test "names the missing scope's error in the challenge" do
      conn = FallbackController.call(build_conn(), {:error, :insufficient_scope})

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer error="insufficient_scope")
             ]
    end
  end
end
