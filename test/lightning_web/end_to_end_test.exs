defmodule LightningWeb.EndToEndTest do
  use LightningWeb.ConnCase, async: true
  use Oban.Testing, repo: Lightning.Repo

  import Lightning.{
    JobsFixtures,
    CredentialsFixtures,
    ProjectsFixtures
  }

  alias Lightning.Invocation

  setup :register_and_log_in_superuser

  defp expected_core, do: "│ ◲ ◱  @openfn/core#v1.4.7 (Node.js v16.15.0"
  defp expected_adaptor, do: "@openfn/language-http@4.0.0"

  test "the whole thing", %{conn: conn} do
    project = project_fixture()

    project_credential =
      project_credential_fixture(
        name: "test credential",
        body: %{"username" => "quux", "password" => "immasecret"},
        project_id: project.id
      )

    webhook_job =
      job_fixture(
        adaptor: "@openfn/language-http",
        body: webhook_expression(),
        project_id: project.id,
        project_credential_id: project_credential.id
      )

    flow_job =
      job_fixture(
        adaptor: "@openfn/language-http",
        body: flow_expression(),
        project_id: project.id,
        project_credential_id: project_credential.id,
        trigger: %{type: :on_job_success, upstream_job_id: webhook_job.id}
      )

    _catch_job =
      job_fixture(
        adaptor: "@openfn/language-http",
        body: catch_expression(),
        project_id: project.id,
        project_credential_id: project_credential.id,
        trigger: %{type: :on_job_failure, upstream_job_id: flow_job.id}
      )

    Oban.Testing.with_testing_mode(:manual, fn ->
      message = %{"a" => 1}

      conn = post(conn, "/i/#{webhook_job.id}", message)

      event_id = Jason.decode!(conn.resp_body) |> Map.get("event_id")

      assert %{"event_id" => _, "run_id" => _} = json_response(conn, 200)

      assert_enqueued(
        worker: Lightning.Pipeline,
        args: %{event_id: event_id}
      )

      # All runs should use Oban
      assert %{success: 3, cancelled: 0, discard: 0, failure: 0, snoozed: 0} ==
               Oban.drain_queue(Oban, queue: :runs, with_recursion: true)

      [run_3, run_2, run_1] = Invocation.list_runs_for_project(project).entries

      # Run 1 should succeed and use the appropriate packages
      assert run_1.finished_at != nil
      assert run_1.exit_code == 0
      assert run_1.event_id == event_id
      assert run_1.log |> Enum.at(1) =~ expected_core()
      assert run_1.log |> Enum.at(2) =~ expected_adaptor()
      assert run_1.log |> Enum.at(4) == "2"
      assert run_1.log |> Enum.at(5) == "{ name: 'ศผ่องรี มมซึฆเ' }"
      assert run_1.log |> Enum.at(-1) == "Finished."

      #  Run 2 should fail but not expose a secret
      assert run_2.finished_at != nil
      assert run_2.exit_code == 1

      assert run_2.log |> Enum.at(4) ==
               "{ password: '***', username: 'quux' }"

      #  Run 3 should succeed and log "6"
      assert run_3.finished_at != nil
      assert run_3.exit_code == 0
      assert run_3.log |> Enum.at(4) == "6"
    end)
  end

  defp webhook_expression do
    "fn(state => {
      state.x = state.data.a * 2;
      console.log(state.x);
      console.log({name: 'ศผ่องรี มมซึฆเ'})
      return state;
    });"
  end

  defp flow_expression do
    "fn(state => {
      console.log(state.configuration);
      throw 'fail!'
    })"
  end

  defp catch_expression do
    "fn(state => {
      state.x = state.x * 3;
      console.log(state.x);
      return state;
    });"
  end

  # Add a cron expression test next
  # def cron_expression do
  #   "fn(state => {
  #     console.log(state.configuration);
  #     state.configuration = 'bad'
  #     if (state.references) {
  #       state.references.push('ok');
  #     }
  #     console.log(state);
  #     return state;
  #   });"
  # end
end
