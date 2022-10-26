defmodule Lightning.Pipeline.RunnerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Pipeline
  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  import Lightning.CredentialsFixtures
  import Lightning.ProjectsFixtures

  test "start/2 takes a run and executes it" do
    project = project_fixture()
    credential_body = %{"username" => "quux", "password" => "immasecret"}

    project_credential =
      project_credential_fixture(
        name: "test credential",
        body: credential_body,
        project_id: project.id
      )

    job =
      workflow_job_fixture(
        adaptor: "@openfn/language-common",
        body: """
        alterState(state => {
          return new Promise((resolve, reject) => {
            setTimeout(() => {
              console.log("---")
              console.log(JSON.stringify(state));
              console.log("---")
              resolve(state);
            }, 1);
          });
        });
        """,
        project_id: project.id,
        project_credential_id: project_credential.id
      )

    dataclip_body = %{"foo" => "bar"}

    dataclip =
      dataclip_fixture(
        body: dataclip_body,
        project_id: job.workflow.project_id,
        type: :http_request
      )

    run = run_fixture(job_id: job.id, input_dataclip_id: dataclip.id)
    result = %Engine.Result{} = Pipeline.Runner.start(run)

    expected_state = %{
      "data" => dataclip_body,
      "configuration" => credential_body
    }

    assert File.read!(result.final_state_path)
           |> Jason.decode!() == expected_state

    run =
      Repo.reload!(run)
      |> Repo.preload(:output_dataclip)

    assert run.output_dataclip.body == expected_state

    refute is_nil(run.started_at)
    refute is_nil(run.finished_at)
    assert run.exit_code == 0

    log = Enum.join(run.log, "\n")
    assert log =~ "@openfn/language-common"
    refute log =~ ~S(password":"immasecret")

    assert length(run.log) > 0
  end

  test "create_dataclip_from_result/3" do
    assert Pipeline.Runner.create_dataclip_from_result(
             %Engine.Result{final_state_path: "no_such_path"},
             run_fixture()
           ) == {:error, :enoent}

    assert Pipeline.Runner.create_dataclip_from_result(
             %Engine.Result{
               final_state_path:
                 Temp.open!(%{suffix: ".json"}, &IO.write(&1, ""))
             },
             run_fixture()
           ) == {:error, %Jason.DecodeError{data: "", position: 0}}
  end
end
