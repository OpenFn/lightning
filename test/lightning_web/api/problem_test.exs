defmodule LightningWeb.API.ProblemTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers

  alias Lightning.Extensions.Message
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
    end

    test "an API route takes a request that accepts only application/problem+json" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/problem+json")
        |> get(~p"/api/projects")

      assert get_resp_header(conn, "content-type") == [
               "application/problem+json; charset=utf-8"
             ]

      assert_unauthenticated(conn, :unauthenticated, ["Bearer"])
    end

    test "sends the problem's entries, extensions and headers" do
      problem =
        Problem.new(:not_ready,
          headers: [{"retry-after", "5"}],
          extensions: %{work_order_id: "wo-1"}
        )

      conn = respond(nil, problem)

      assert get_resp_header(conn, "retry-after") == ["5"]

      assert %{"work_order_id" => "wo-1"} =
               assert_problem(conn, 503, :not_ready, [])
    end

    test "replaces a header the conn already had, so it is sent once with the problem's value" do
      conn =
        build_conn()
        |> put_resp_header("www-authenticate", "Basic")
        |> put_resp_header("retry-after", "1")
        |> Problem.respond(
          Problem.new(:not_ready,
            headers: [{"www-authenticate", "Bearer"}, {"retry-after", "5"}]
          )
        )

      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
      assert get_resp_header(conn, "retry-after") == ["5"]
    end
  end

  describe "new/2" do
    test "takes a status a code may also answer with" do
      problem = Problem.new(:exceeds_limit, status: 429)

      assert problem.status == 429
      assert Problem.body(problem).title == "Too Many Requests"
    end

    test "refuses a status the code never answers with" do
      assert_raise ArgumentError, ":not_found is never sent at 429", fn ->
        Problem.new(:not_found, status: 429)
      end
    end
  end

  describe "FallbackController" do
    test "answers the results no route shows, and the limiter reasons, with one status and code" do
      for {result, status, code} <- [
            {{:error, :no_such_project}, 404, :not_found},
            {{:error, :workflow_deleted}, 404, :not_found},
            {{:error, :exceeds_limit}, 402, :exceeds_limit},
            {{:error, :runs_hard_limit, %Message{}}, 402, :exceeds_limit},
            {{:error, :too_many_runs, %Message{}}, 429, :too_many_runs},
            {{:error, :too_many_workflows, %Message{}}, 402, :exceeds_limit},
            {{:error, :unknown_project, %Message{}}, 404, :not_found}
          ] do
        build_conn()
        |> FallbackController.call(result)
        |> assert_problem(status, code, [])
      end
    end
  end
end
