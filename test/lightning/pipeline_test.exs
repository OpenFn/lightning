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
    test "starts a run for a given event and executes its on_job_failure downstream job" do
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
               "configuration" => %{"credential" => "body"},
               "data" => %{},
               "error" => error
             } = expected_run.output_dataclip.body

      error = Enum.slice(error, 0..4)

      [
        ~r/╭─[─]+─╮/,
        ~r/│ ◲ ◱ [ ]+@openfn\/core#v1.4.8 \(Node.js v1[\d\.]+\) │/,
        ~r/│ ◳ ◰ [ ]+@openfn\/language-common@[\d\.]+ │/,
        ~r/╰─[─]+─╯/,
        "Error: I'm supposed to fail."
      ]
      |> Enum.zip(error)
      |> Enum.each(fn {m, l} ->
        assert l =~ m
      end)
    end

    # test "starts a run for a given event and executes its on_job_success downstream job" do
    #   project = project_fixture()

    #   project_credential =
    #     credential_fixture(project_credentials: [%{project_id: project.id}])
    #     |> Map.get(:project_credentials)
    #     |> List.first()

    #   other_project_credential =
    #     credential_fixture(
    #       name: "my credential",
    #       body: %{"credential" => "body"},
    #       project_credentials: [%{project_id: project.id}]
    #     )
    #     |> Map.get(:project_credentials)
    #     |> List.first()

    #   job =
    #     job_fixture(
    #       body: ~s[fn(state => { return {...state, extra: "data"} })],
    #       project_credential_id: project_credential.id,
    #       project_id: project.id
    #     )

    #   %{id: downstream_job_id} =
    #     job_fixture(
    #       trigger: %{type: :on_job_success, upstream_job_id: job.id},
    #       name: "on previous job success",
    #       body: ~s[fn(state => state)],
    #       project_id: project.id,
    #       project_credential_id: other_project_credential.id
    #     )

    #   event = event_fixture(job_id: job.id)

    #   run_fixture(
    #     event_id: event.id,
    #     project_id: event.project_id,
    #     job_id: job.id,
    #     input_dataclip_id: event.dataclip_id
    #   )

    #   Pipeline.process(event)

    #   expected_event =
    #     from(e in Lightning.Invocation.Event,
    #       where: e.job_id == ^downstream_job_id,
    #       preload: [:result_dataclip]
    #     )
    #     |> Repo.one!()

    #   assert %{
    #            "configuration" => %{"credential" => "body"},
    #            "data" => %{},
    #            "extra" => "data"
    #          } == expected_event.result_dataclip.body
    # end
  end
end
