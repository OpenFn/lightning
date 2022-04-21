defmodule Lightning.RunnerTest do
  use Lightning.DataCase, async: true

  alias Lightning.{Invocation, Runner}
  import Lightning.JobsFixtures

  test "does something" do
    credential_body = %{"username" => "quux"}

    job =
      job_fixture(
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
        credential: %{name: "test credential", body: credential_body}
      )

    dataclip_body = %{"foo" => "bar"}
    expected_state = %{"data" => dataclip_body, "configuration" => credential_body}

    {:ok, %{run: run}} =
      Invocation.create(
        %{job_id: job.id, type: :webhook},
        %{type: :http_request, body: dataclip_body}
      )

    result = %Engine.Result{} = Runner.start(run)

    assert File.read!(result.final_state_path)
           |> Jason.decode!() == expected_state

    run = Repo.reload!(run)
    refute is_nil(run.started_at)
    refute is_nil(run.finished_at)
    assert run.exit_code == 0

    log = Enum.join(run.log, "\n")
    assert log =~ "@openfn/language-common"

    assert length(run.log) > 0
  end
end
