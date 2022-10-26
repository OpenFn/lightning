defmodule Lightning.Invocation.AttemptTest do
  use Lightning.DataCase, async: true

  alias Lightning.Attempt

  describe "changeset/2" do
    test "must have a reason" do
      errors = Attempt.changeset(%Attempt{}, %{}) |> errors_on()

      assert errors[:reason_id] == ["can't be blank"]
    end

    test "must have a work_order" do
      errors = Attempt.changeset(%Attempt{}, %{}) |> errors_on()

      assert errors[:work_order_id] == ["can't be blank"]
    end
  end
end
