defmodule Lightning.Invocation.RunTest do
  use Lightning.DataCase, async: true

  alias Lightning.Run

  describe "changeset/2" do
    test "must have a work_order" do
      errors = Run.changeset(%Run{}, %{}) |> errors_on()

      assert errors[:work_order_id] == ["can't be blank"]
    end
  end
end
