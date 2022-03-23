defmodule Lightning.Jobs.JobTest do
  use Lightning.DataCase

  alias Lightning.Jobs.Job

  defp random_job_name(length) do
    for _ <- 1..length,
        into: "",
        do: <<Enum.random('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ')>>
  end

  describe "changeset/2" do
    test "must have a trigger" do
      errors = Job.changeset(%Job{}, %{}) |> errors_on()

      assert errors[:trigger] == ["can't be blank"]
    end

    test "name can't be longer than 100 chars" do
      name = random_job_name(101)
      errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()
      assert errors[:name] == ["should be at most 100 character(s)"]
    end

    test "name can't contain non url-safe chars" do
      ["My project @ OpenFn", "Can't have a / slash"]
      |> Enum.each(fn name ->
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()
        assert errors[:name] == ["has invalid format"]
      end)
    end
  end
end
