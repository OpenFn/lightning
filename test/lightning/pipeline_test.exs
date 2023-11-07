defmodule Lightning.PipelineTest do
  alias Lightning.Invocation
  use Lightning.DataCase, async: true
  use Mimic

  alias Lightning.Pipeline
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}

  import Lightning.Factories

  describe "process/1 with an attempt" do
    @tag :skip
    test "creates an initial attempt run" do
      workflow = insert(:simple_workflow)

      dataclip = insert(:dataclip, project: workflow.project)

      reason =
        insert(:reason,
          dataclip: dataclip,
          trigger: workflow.triggers |> List.first(),
          type: :webhook
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)
      attempt = insert(:attempt, reason: reason, work_order: work_order)

      Pipeline.process(attempt)
    end
  end

  describe "process/1 with an attempt run" do
    @tag :skip
    test "starts a run for a given AttemptRun and executes its on_job_failure downstream job" do
      workflow = insert(:workflow)

      job =
        insert(:job,
          name: "job 1",
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })],
          workflow: workflow
        )

      %{id: downstream_job_id} =
        insert(:job,
          workflow: workflow,
          project_credential_id:
            insert(:project_credential,
              credential:
                insert(:credential,
                  name: "my credential",
                  body: %{"credential" => "body"}
                )
            ).id
        )

      # add an edge to connect the two jobs
      insert(:edge, %{
        source_job_id: job.id,
        workflow: workflow,
        target_job_id: downstream_job_id,
        condition: :on_job_failure
      })

      dataclip = insert(:dataclip)

      reason =
        insert(:reason,
          type: :webhook,
          dataclip_id: dataclip.id
        )

      work_order = insert(:workorder, reason: reason, workflow: workflow)

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

    @tag :skip
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

      dataclip = insert(:dataclip)

      reason =
        insert(:reason,
          type: :webhook,
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)

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
    @tag :skip
    test "logs_for_run/1 returns an array of the logs for a given run" do
      run =
        insert(:run,
          log_lines: [%{body: "Hello"}, %{body: "I am a"}, %{body: "log"}]
        )

      log_lines = Invocation.logs_for_run(run)

      assert Enum.count(log_lines) == 3

      assert log_lines |> Enum.map(fn log_line -> log_line.body end) == [
               "Hello",
               "I am a",
               "log"
             ]
    end

    @tag :skip
    test "assemble_logs_for_run/1 returns a string representation of the logs for a run" do
      run =
        insert(:run,
          log_lines: [%{body: "Hello"}, %{body: "I am a"}, %{body: "log"}]
        )

      log_string = Invocation.assemble_logs_for_run(run)

      assert log_string == "Hello\nI am a\nlog"
    end

    @tag :skip
    test "assemble_logs_for_run/1 returns nil when given a nil run" do
      assert Invocation.assemble_logs_for_run(nil) == nil
    end
  end
end
