defmodule Lightning.RunnerTest do
  use Lightning.DataCase

  alias Lightning.{Invocation, Runner}
  import Lightning.JobsFixtures

  test "does something" do
    job =
      job_fixture(
        adaptor: "@openfn/language-common",
        body: """
        alterState(state => {
          return new Promise((resolve, reject) => {
            setTimeout(() => {
              resolve(state);
            }, 1);
          });
        });
        """
      )

    {:ok, %{run: run}} =
      Invocation.create(
        %{job_id: job.id, type: :webhook},
        %{type: :http_request, body: %{"foo" => "bar"}}
      )

    :ok = Runner.start(run)

    run = Repo.reload!(run)
    refute is_nil(run.started_at)
    refute is_nil(run.finished_at)
    assert run.exit_code == 0

    log = Enum.join(run.log, "\n")
    assert log =~ "@openfn/language-common"

    assert length(run.log) > 0
  end
end
