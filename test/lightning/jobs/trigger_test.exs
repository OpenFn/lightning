defmodule Lightning.Jobs.TriggerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Jobs.Trigger
  import Lightning.JobsFixtures

  describe "changeset/2" do
    test "type must be valid" do
      errors = Trigger.changeset(%Trigger{}, %{type: :foo}) |> errors_on()
      assert errors[:type] == ["is invalid"]

      errors = Trigger.changeset(%Trigger{}, %{type: :webhook}) |> errors_on()
      assert errors[:type] == nil
    end

    test "must have an upstream job when type is :on_job_success" do
      errors = Trigger.changeset(%Trigger{}, %{type: :on_job_success}) |> errors_on()
      assert errors[:upstream_job_id] == ["can't be blank"]
      assert errors[:type] == nil

      job = job_fixture()

      errors =
        Trigger.changeset(%Trigger{}, %{type: :on_job_success, upstream_job_id: job.id})
        |> errors_on()

      assert errors[:upstream_job_id] == nil
      assert errors[:type] == nil
    end
  end
end
