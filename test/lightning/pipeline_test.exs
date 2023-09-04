defmodule Lightning.PipelineTest do
  use Lightning.DataCase, async: true
  use Mimic

  alias Lightning.Pipeline
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}

  import Lightning.InvocationFixtures
  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.Factories

  describe "process/1" do
    test "starts a run for a given AttemptRun and executes its on_job_failure downstream job" do
      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          name: "job 1",
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })]
        )

      %{id: downstream_job_id} =
        job_fixture(
          name: "job 2",
          trigger: %{type: :on_job_failure, upstream_job_id: job.id},
          body: ~s[fn(state => state)],
          workflow_id: job.workflow_id,
          project_credential_id:
            project_credential_fixture(
              name: "my credential",
              body: %{"credential" => "body"}
            ).id
        )

      # add an edge to connect the two jobs
      insert(:edge, %{
        source_job_id: job.id,
        workflow: job.workflow,
        target_job_id: downstream_job_id,
        condition: :on_job_failure
      })

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      {:ok, attempt_run} =
        AttemptRun.new(
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          }),
          Run.changeset(%Run{}, %{
            project_id: job.workflow.project_id,
            job_id: job.id,
            input_dataclip_id: dataclip.id
          })
        )
        |> Repo.insert()

      Pipeline.process(attempt_run)

      previous_id = attempt_run.run.id

      expected_run =
        from(r in Lightning.Invocation.Run,
          where:
            r.job_id == ^downstream_job_id and
              r.previous_id == ^previous_id,
          preload: [:output_dataclip]
        )
        |> Repo.one!()

      assert expected_run.input_dataclip_id == dataclip.id

      assert %{
               "data" => %{},
               "error" => error
             } = expected_run.output_dataclip.body

      assert error |> Enum.join("\n") =~ "Error: I'm supposed to fail"
    end

    test "starts a run for a given AttemptRun and executes its on_job_success downstream job" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)

      job =
        insert(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          name: "1",
          workflow: workflow
        )

      insert(:edge, %{
        workflow: workflow,
        source_trigger: trigger,
        target_job: job
      })

      credential =
        insert(:credential,
          name: "my credential",
          body: %{"apiToken" => "secret123"}
        )

      downstream_job =
        insert(:job, %{
          workflow: workflow,
          project_credential:
            build(:project_credential, project: project, credential: credential)
        })

      insert(:edge, %{
        workflow: workflow,
        source_job: job,
        target_job: downstream_job,
        condition: :on_job_success
      })

      disabled_downstream_job =
        insert(:job,
          enabled: false,
          body: ~s[fn(state => state)],
          workflow: workflow,
          name: "3"
        )

      insert(:edge, %{
        source_job: job,
        workflow: job.workflow,
        target_job: disabled_downstream_job,
        condition: :on_job_success
      })

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      {:ok, attempt_run} =
        AttemptRun.new(
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          }),
          Run.changeset(%Run{}, %{
            project_id: job.workflow.project_id,
            job_id: job.id,
            input_dataclip_id: dataclip.id
          })
        )
        |> Repo.insert()

      Pipeline.process(attempt_run)

      previous_id = attempt_run.run.id

      output_dataclip_id =
        attempt_run.run |> Repo.reload!() |> Map.get(:output_dataclip_id)

      expected_run =
        from(r in Lightning.Invocation.Run,
          where: r.previous_id == ^previous_id,
          preload: [:output_dataclip]
        )
        |> Repo.one!()

      assert expected_run.input_dataclip_id == output_dataclip_id

      assert expected_run.credential_id == credential.id

      assert %{
               "data" => %{}
             } = expected_run.output_dataclip.body

      assert %{
               "data" => %{},
               "extra" => "data"
             } = expected_run.output_dataclip.body
    end
  end

  describe "run logs" do
    test "logs_for_run/1 returns an array of the logs for a given run" do
      run =
        run_fixture(
          log_lines: [%{body: "Hello"}, %{body: "I am a"}, %{body: "log"}]
        )

      log_lines = Pipeline.logs_for_run(run)

      assert Enum.count(log_lines) == 3

      assert log_lines |> Enum.map(fn log_line -> log_line.body end) == [
               "Hello",
               "I am a",
               "log"
             ]
    end

    test "assemble_logs_for_run/1 returns a string representation of the logs for a run" do
      run =
        run_fixture(
          log_lines: [%{body: "Hello"}, %{body: "I am a"}, %{body: "log"}]
        )

      log_string = Pipeline.assemble_logs_for_run(run)

      assert log_string == "Hello\nI am a\nlog"
    end

    test "assemble_logs_for_run/1 returns nil when given a nil run" do
      assert Pipeline.assemble_logs_for_run(nil) == nil
    end
  end
end
