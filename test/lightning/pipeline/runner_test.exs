defmodule Lightning.Pipeline.RunnerTest do
  alias Lightning.Invocation
  use Lightning.DataCase, async: false

  alias Lightning.Pipeline

  import Lightning.{
    JobsFixtures,
    InvocationFixtures,
    CredentialsFixtures,
    ProjectsFixtures,
    BypassHelpers
  }

  alias Lightning.Pipeline.Runner

  test "start/2 takes a run and executes it" do
    project = project_fixture()
    credential_body = %{"username" => "quux", "password" => "immasecret"}

    project_credential =
      project_credential_fixture(
        name: "test credential",
        body: credential_body,
        project_id: project.id
      )

    %{job: job} =
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
        project: project,
        project_credential: project_credential
      )

    dataclip_body = %{"foo" => "bar"}

    dataclip =
      dataclip_fixture(
        body: dataclip_body,
        project_id: job.workflow.project_id,
        type: :http_request
      )

    run = run_fixture(job_id: job.id, input_dataclip_id: dataclip.id)
    result = %Lightning.Runtime.Result{} = Pipeline.Runner.start(run)

    expected_state = %{
      "data" => dataclip_body
    }

    assert File.read!(result.final_state_path)
           |> Jason.decode!() == expected_state

    run =
      Repo.reload!(run)
      |> Repo.preload(:output_dataclip)

    expected_run_result_body = %{
      "data" => dataclip_body
    }

    assert run.output_dataclip.body == expected_run_result_body

    refute is_nil(run.started_at)
    refute is_nil(run.finished_at)
    assert run.exit_code == 0

    log = Invocation.assemble_logs_for_run(run)
    # assert log =~ "@openfn/language-common"
    refute log =~ ~S(password":"immasecret")

    assert Invocation.logs_for_run(run) |> length() > 0

    refute Repo.all(Lightning.Invocation.Dataclip)
           |> Enum.any?(fn result ->
             Map.has_key?(result, "configuration")
           end)
  end

  test "start/2 takes a run and executes it, refreshing the oauth token if required" do
    bypass = Bypass.open()

    Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
      google: [
        client_id: "foo",
        client_secret: "bar",
        wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known"
      ]
    )

    expect_wellknown(bypass)

    expect_token(bypass, Lightning.AuthProviders.Google.get_wellknown!())
    expires_at = DateTime.to_unix(DateTime.utc_now())

    user = Lightning.AccountsFixtures.user_fixture()

    project = project_fixture(project_users: [%{user_id: user.id}])

    project_credential =
      project_credential_fixture(
        user_id: user.id,
        name: "test credential",
        body: %{
          "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
          "expires_at" => expires_at,
          "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
          "scope" => "https://www.googleapis.com/auth/spreadsheets"
        },
        schema: "googlesheets",
        project_id: project.id
      )

    %{job: job} =
      workflow_job_fixture(
        adaptor: "@openfn/language-common",
        body: """
        fn(state => {
          console.log(state.configuration)
          return state;
        });
        """,
        project: project,
        project_credential: project_credential
      )

    dataclip_body = %{"foo" => "bar"}

    dataclip =
      dataclip_fixture(
        body: dataclip_body,
        project_id: job.workflow.project_id,
        type: :http_request
      )

    run = run_fixture(job_id: job.id, input_dataclip_id: dataclip.id)

    result = %Lightning.Runtime.Result{} = Pipeline.Runner.start(run)

    new_expiry =
      Lightning.Credentials.Credential
      |> Repo.get(project_credential.credential_id)
      |> Map.get(:body)
      |> Map.get("expires_at")

    assert new_expiry > expires_at + 3599
    assert Enum.at(result.log, 11) =~ "expires_at\":#{new_expiry}"
  end

  test "scrub_result/1 removes :configuration from a map" do
    map = %{"data" => true, "configuration" => %{"secret" => "hello"}}
    assert Runner.scrub_result(map) == %{"data" => true}
  end

  test "create_dataclip_from_result/3" do
    assert Pipeline.Runner.create_dataclip_from_result(
             %Lightning.Runtime.Result{final_state_path: "no_such_path"},
             run_fixture()
           ) == {:error, :enoent}

    assert Pipeline.Runner.create_dataclip_from_result(
             %Lightning.Runtime.Result{
               final_state_path:
                 Temp.open!(%{suffix: ".json"}, &IO.write(&1, ""))
             },
             run_fixture()
           ) == {:error, %Jason.DecodeError{data: "", position: 0}}
  end
end
