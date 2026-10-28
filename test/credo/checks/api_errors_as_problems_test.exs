Code.require_file("../../../credo/checks/api_errors_as_problems.ex", __DIR__)

defmodule Lightning.Credo.Check.ApiErrorsAsProblemsTest do
  use Credo.Test.Case

  alias Lightning.Credo.Check.ApiErrorsAsProblems

  test "an API controller setting a 4xx or 5xx status itself is flagged" do
    for {line, trigger} <- [
          {"conn |> put_status(:not_found) |> json(%{})", "put_status"},
          {"conn |> put_status(422) |> json(%{})", "put_status"},
          {"put_status(conn, :forbidden)", "put_status"},
          {"put_status(conn, 500)", "put_status"},
          {"Plug.Conn.put_status(conn, :bad_request)", "put_status"},
          {"conn |> send_resp(404, \"\")", "send_resp"},
          {"send_resp(conn, :service_unavailable, \"\")", "send_resp"},
          {"conn |> resp(:unprocessable_entity, \"\")", "resp"},
          {"resp(conn, 409, \"\")", "resp"}
        ] do
      """
      defmodule LightningWeb.API.ThingController do
        def show(conn, _params), do: #{line}
      end
      """
      |> to_source_file()
      |> run_check(ApiErrorsAsProblems)
      |> assert_issue(fn issue ->
        assert issue.trigger == trigger, "for: #{line}"
        assert issue.line_no == 2
      end)
    end
  end

  test "success statuses, statuses in a variable and Problem.respond are clean" do
    """
    defmodule LightningWeb.API.ThingController do
      alias LightningWeb.API.Problem

      def create(conn, _params), do: conn |> put_status(:created) |> json(%{})
      def index(conn, _params), do: conn |> put_status(200) |> json(%{})
      def ok(conn, _params), do: put_status(conn, :ok)
      def delete(conn, _params), do: send_resp(conn, :no_content, "")
      def export(conn, _params), do: conn |> send_resp(201, "")
      def head(conn, _params), do: resp(conn, 204, "")
      def proxy(conn, status), do: conn |> put_status(status) |> json(%{})

      def show(conn, _params) do
        :not_found
        |> Problem.new()
        |> Problem.respond(conn)
      end
    end
    """
    |> to_source_file()
    |> run_check(ApiErrorsAsProblems)
    |> refute_issues()
  end
end
