defmodule Lightning.Invocation.RunTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation.Run
  import Ecto.Changeset, only: [get_field: 2]

  @tag skip: "deprecated"
  describe "new_from/2" do
    test "returns a new Run changeset based off another" do
      run =
        Lightning.InvocationFixtures.run_fixture(
          started_at: DateTime.utc_now(),
          finished_at: DateTime.utc_now(),
          log_lines: [%{body: "log"}, %{body: "line"}]
        )
        |> Repo.preload(:log_lines)

      new_run = Run.new_from(run)

      refute get_field(new_run, :id) == run.id
      refute get_field(new_run, :log_lines) == run.log_lines
      assert get_field(new_run, :job_id) == run.job_id
      assert get_field(new_run, :input_dataclip_id) == run.input_dataclip_id
      assert get_field(new_run, :previous_id) == run.previous_id
      assert get_field(new_run, :started_at) == nil
      assert get_field(new_run, :finished_at) == nil
    end
  end
end
