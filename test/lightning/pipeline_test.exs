defmodule Lightning.PipelineTest do
  use Lightning.DataCase, async: true
  use Mimic

  alias Lightning.Pipeline
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}

  import Lightning.InvocationFixtures
  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures

  describe "process/1" do
    test "starts a run for a given AttemptRun and executes its on_job_failure downstream job" do
      job =
        workflow_job_fixture(
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })]
        )

      %{id: downstream_job_id} =
        job_fixture(
          trigger: %{type: :on_job_failure, upstream_job_id: job.id},
          body: ~s[fn(state => state)],
          workflow_id: job.workflow_id,
          project_credential_id:
            project_credential_fixture(
              name: "my credential",
              body: %{"credential" => "body"}
            ).id
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job.trigger.id,
          dataclip_id: dataclip.id
        )

      {:ok, attempt_run} =
        AttemptRun.new()
        |> Ecto.Changeset.put_assoc(
          :attempt,
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          })
        )
        |> Ecto.Changeset.put_assoc(
          :run,
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
      job =
        workflow_job_fixture(
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      %{id: _downstream_job_id} =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job.id},
          body: ~s[fn(state => state)],
          workflow_id: job.workflow_id,
          project_credential_id:
            project_credential_fixture(
              name: "my credential",
              body: %{"credential" => "body"}
            ).id
        )

      %{id: _disabled_downstream_job_id} =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job.id},
          enabled: false,
          body: ~s[fn(state => state)],
          workflow_id: job.workflow_id
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job.trigger.id,
          dataclip_id: dataclip.id
        )

      {:ok, attempt_run} =
        AttemptRun.new()
        |> Ecto.Changeset.put_assoc(
          :attempt,
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          })
        )
        |> Ecto.Changeset.put_assoc(
          :run,
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

      assert %{
               "data" => %{}
             } = expected_run.output_dataclip.body

      assert %{
               "data" => %{},
               "extra" => "data"
             } = expected_run.output_dataclip.body
    end
  end
end
