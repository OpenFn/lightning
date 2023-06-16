defmodule LightningWeb.EndToEndTest do
  use LightningWeb.ConnCase, async: true
  use Oban.Testing, repo: Lightning.Repo

  import Lightning.JobsFixtures

  alias Lightning.Pipeline
  import Lightning.Factories

  alias Lightning.Invocation

  import Ecto.Query

  setup :register_and_log_in_superuser

  # defp expected_core, do: "│ ◲ ◱  @openfn/core#v1.4.8 (Node.js v18.12.0"
  # defp expected_adaptor, do: "@openfn/language-http@4.2.3"

  # workflow runs webhook then flow job
  test "the whole thing", %{conn: conn} do
    project = insert(:project)

    project_credential =
      insert(:project_credential,
        credential: %{
          name: "test credential",
          body: %{"username" => "quux", "password" => "immasecret"}
        },
        project: project
      )

    %{
      job: first_job = %{workflow: workflow},
      trigger: webhook_trigger,
      edge: _edge
    } =
      workflow_job_fixture(
        project: project,
        name: "1st-job",
        adaptor: "@openfn/language-http",
        body: webhook_expression(),
        project_credential: project_credential
      )

    # add an edge that follows the new rules foe edges
    # delete the current trigger for this flow job as it will have an edge
    flow_job =
      insert(:job,
        name: "2nd-job",
        adaptor: "@openfn/language-http",
        body: flow_expression(),
        workflow: workflow,
        project_credential: project_credential
      )

    insert(:edge, %{
      workflow: workflow,
      source_job_id: first_job.id,
      target_job_id: flow_job.id,
      condition: :on_job_success
    })

    catch_job =
      insert(:job,
        name: "3rd-job",
        adaptor: "@openfn/language-http",
        body: catch_expression(),
        workflow: workflow,
        project_credential: project_credential
      )

    insert(:edge, %{
      source_job_id: flow_job.id,
      workflow: workflow,
      target_job_id: catch_job.id,
      condition: :on_job_failure
    })

    Oban.Testing.with_testing_mode(:manual, fn ->
      message = %{"a" => 1}

      conn = post(conn, "/i/#{webhook_trigger.id}", message)

      assert %{"run_id" => run_id, "attempt_id" => attempt_id} =
               json_response(conn, 200)

      attempt_run =
        Lightning.Repo.get_by(Lightning.AttemptRun,
          run_id: run_id,
          attempt_id: attempt_id
        )

      assert_enqueued(
        worker: Lightning.Pipeline,
        args: %{attempt_run_id: attempt_run.id}
      )

      from(r in Lightning.Invocation.Run, where: r.id == ^attempt_run.run_id)
      |> Lightning.Repo.all()
      |> then(fn [r] ->
        p =
          Ecto.assoc(r, [:job, :project])
          |> Lightning.Repo.one!()

        assert p.id == project.id, "run is associated with a different project"
      end)

      # All runs should use Oban
      assert %{success: 3, cancelled: 0, discard: 0, failure: 0, snoozed: 0} ==
               Oban.drain_queue(Oban, queue: :runs, with_recursion: true)

      [run_3, run_2, run_1] = Invocation.list_runs_for_project(project).entries

      # Run 1 should succeed and use the appropriate packages
      assert run_1.finished_at != nil
      assert run_1.exit_code == 0
      assert Pipeline.assemble_logs_for_run(run_1) =~ "Done in"

      #  Run 2 should fail but not expose a secret
      assert run_2.finished_at != nil
      assert run_2.exit_code == 1

      log = Pipeline.assemble_logs_for_run(run_2)

      assert log =~
               ~S[{"password":"***","username":"quux"}]

      #  Run 3 should succeed and log "6"
      assert run_3.finished_at != nil
      assert run_3.exit_code == 0
      log = Pipeline.assemble_logs_for_run(run_3)
      assert log =~ "[JOB] ℹ 6"
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
end
