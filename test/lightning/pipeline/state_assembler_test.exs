defmodule Lightning.Pipeline.StateAssemblerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Pipeline.StateAssembler
  alias Lightning.Invocation.{Run, Dataclip}
  alias Lightning.Jobs.{Job}

  import Lightning.WorkflowsFixtures
  import Lightning.InvocationFixtures
  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Ecto.Changeset

  describe "assemble/2" do
    test "run with no previous run" do
      %{job: job} = webhook_workflow()

      dataclip = dataclip_fixture(type: :http_request, body: %{"foo" => "bar"})

      run =
        Run.new(%{
          job_id: job.id,
          input_dataclip_id: dataclip.id,
          exit_code: 0,
          log_lines: [%{body: "I've succeeded, log log"}]
        })
        |> Repo.insert!()

      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => %{"my" => "credential"},
               "data" => %{"foo" => "bar"}
             }

      # When a Job doesn't have a credential
      job |> Job.changeset(%{project_credential_id: nil}) |> Repo.update!()

      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => nil,
               "data" => %{"foo" => "bar"}
             }
    end

    test "run whose previous run failed" do
      %{job: job} = webhook_workflow()

      dataclip = dataclip_fixture(type: :http_request, body: %{"foo" => "bar"})

      failed_run =
        Run.new(%{
          job_id: job.id,
          input_dataclip_id: dataclip.id,
          exit_code: 1,
          log_lines: [%{body: "I've failed, log log"}]
        })
        |> Repo.insert!()

      on_fail_job =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job.id},
          project_credential_id:
            project_credential_fixture(
              body: %{"other" => "credential"},
              name: "other credential"
            ).id
        )

      run =
        Run.new(%{
          job_id: on_fail_job.id,
          input_dataclip_id: dataclip.id,
          previous_id: failed_run.id
        })
        |> Repo.insert!()

      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => %{"other" => "credential"},
               "error" => ["I've failed, log log"],
               "data" => %{"foo" => "bar"}
             }
    end

    test "run whose previous run succeeded" do
      %{job: job, workflow: workflow} = webhook_workflow()

      dataclip = dataclip_fixture(type: :http_request, body: %{"foo" => "bar"})

      previous_run =
        Run.new(%{
          job_id: job.id,
          input_dataclip_id: dataclip.id,
          exit_code: 0,
          log_lines: [%{body: "I've succeeded, log log"}]
        })
        |> put_assoc(
          :output_dataclip,
          Dataclip.new(%{
            type: :run_result,
            body: %{"data" => %{"foo" => "bar"}, "extra" => "state"},
            project_id: workflow.project_id
          })
        )
        |> Repo.insert!()

      on_success_job =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job.id},
          project_credential_id:
            project_credential_fixture(
              body: %{"on_success" => "credential"},
              name: "other credential"
            ).id
        )

      run =
        Run.new(%{
          job_id: on_success_job.id,
          input_dataclip_id: previous_run.output_dataclip.id,
          previous_id: previous_run.id
        })
        |> Repo.insert!()

      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => %{"on_success" => "credential"},
               "data" => %{"foo" => "bar"},
               "extra" => "state"
             }
    end
  end

  def webhook_workflow() do
    workflow = build_workflow()

    {:ok, %{workflow: workflow} = job} =
      Job.new()
      |> Job.put_workflow(workflow)
      |> Job.put_project_credential(
        project_credential_fixture(
          body: %{"my" => "credential"},
          name: "My Credential"
        )
      )
      |> Job.changeset(%{
        body: "fn(state => state)",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common"
      })
      |> Repo.insert()

    %{workflow: workflow, job: job}
  end
end
