defmodule Lightning.CrashTest do
  use Lightning.DataCase, async: true
  use Oban.Testing, repo: Lightning.Repo

  alias Lightning.Pipeline
  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  import Lightning.CredentialsFixtures
  import Lightning.ProjectsFixtures

  describe "Crash test" do
    test "timeout jobs generate results with :killed status" do
      Application.put_env(:lightning, :max_run_duration, 5 * 1000)
      project = project_fixture()

      project_credential =
        project_credential_fixture(
          name: "test credential",
          body: %{"username" => "foo", "password" => "bar"},
          project_id: project.id
        )

      job =
        workflow_job_fixture(
          adaptor: "@openfn/language-common",
          body: """
          fn(state => {
            return new Promise((resolve, reject) => {
              setTimeout(() => {
                console.log('wait, and then resolve');
                resolve(state);
              }, 10 * 1000);
            });
          });
          """,
          project_id: project.id,
          project_credential_id: project_credential.id
        )

      dataclip =
        dataclip_fixture(
          body: %{"foo" => "bar"},
          project_id: project.id,
          type: :http_request
        )

      run = run_fixture(job_id: job.id, input_dataclip_id: dataclip.id)
      result = %Engine.Result{} = Pipeline.Runner.start(run)

      assert result.exit_reason == :killed
      assert result.exit_code == nil

      assert File.read!(result.final_state_path) == ""

      run =
        Repo.reload!(run)
        |> Repo.preload(:output_dataclip)

      assert run.output_dataclip == nil

      refute is_nil(run.started_at)
      refute is_nil(run.finished_at)
      assert run.exit_code == nil
    end
  end
end
