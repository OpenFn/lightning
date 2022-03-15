defmodule Lightning.Jobs.JobTest do
  use Lightning.DataCase

  alias Lightning.Jobs.Job

  describe "changeset/2" do
    test "must have a trigger" do
      errors = Job.changeset(%Job{}, %{}) |> errors_on()

      assert errors[:trigger] == ["can't be blank"]
    end
  end
end
