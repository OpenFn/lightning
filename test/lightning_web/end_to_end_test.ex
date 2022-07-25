defmodule LightningWeb.EndToEndTest do
  use LightningWeb.ConnCase, async: false
  use Oban.Testing, repo: Lightning.Repo

  import Lightning.{
    ProjectsFixtures,
    JobsFixtures,
    CredentialsFixtures
  }

  alias Lightning.Invocation

  setup :register_and_log_in_superuser

  test "the whole thing", %{conn: conn} do
    project_credential =
      project_credential_fixture(
        name: "test credential",
        body: %{"username" => "quux", "password" => "immasecret"}
      )

    job =
      job_fixture(
        adaptor: "@openfn/language-http",
        body: message_expression(),
        project_id: project_credential.project_id,
        project_credential_id: project_credential.id
      )

    Oban.Testing.with_testing_mode(:manual, fn ->
      message = %{"a" => 1}

      conn = post(conn, "/i/#{job.id}", message)

      event_id = Jason.decode!(conn.resp_body) |> Map.get("event_id")

      assert %{"event_id" => _, "run_id" => run_id} = json_response(conn, 200)

      assert_enqueued(
        worker: Lightning.Pipeline,
        args: %{event_id: event_id}
      )

      assert %{success: 1, cancelled: 0, discard: 0, failure: 0, snoozed: 0} ==
               Oban.drain_queue(Oban, queue: :runs)

      run =
        Invocation.get_run!(run_id)
        |> IO.inspect(label: "the run when it's done")

      assert run.finished_at != nil
      assert run.exit_code == 0
    end)
  end

  defp expected_core, do: "│ ◲ ◱  @openfn/core#v1.4.7 (Node.js v16."
  defp expected_adaptor, do: "@openfn/language-http@4.0.0"

  def message_expression do
    "fn(state => {
      state.x = state.data.a * 2;
      console.log(state.x);
      console.log({name_last: 'มมซึฆเ', name_first: 'ศผ่องรี'})
      return state;
    });"
  end

  def flow_expression do
    "console.log(state.x);
    fail!"
  end

  def catch_expression do
    "fn(state => {
      state.x = state.x * 3;
      console.log(state.x);
      return state;
    });"
  end

  def timer_expression do
    "fn(state => {
      console.log(state.configuration);
      state.configuration = 'bad'
      if (state.references) {
        state.references.push('ok');
      }
      console.log(state);
      return state;
    });"
  end
end
