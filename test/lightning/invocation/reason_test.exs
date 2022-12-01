defmodule Lightning.Invocation.InvocationReasonTest do
  use Lightning.DataCase, async: true

  alias Lightning.InvocationReason

  describe "changeset/2" do
    test "must have a type" do
      errors =
        InvocationReason.changeset(%InvocationReason{}, %{}) |> errors_on()

      assert errors[:type] == ["can't be blank"]
    end

    test "type must be valid" do
      errors =
        InvocationReason.changeset(%InvocationReason{}, %{type: :foo})
        |> errors_on()

      assert errors[:type] == ["is invalid"]

      errors =
        InvocationReason.changeset(%InvocationReason{}, %{type: :webhook})
        |> errors_on()

      assert errors[:type] == nil
    end

    test ":webhook and :cron type reason must have associated trigger" do
      errors =
        InvocationReason.changeset(%InvocationReason{}, %{type: :webhook})
        |> errors_on()

      assert errors[:trigger_id] == ["can't be blank"]

      errors =
        InvocationReason.changeset(%InvocationReason{}, %{
          type: :webhook,
          trigger_id: "trigger"
        })
        |> errors_on()

      assert errors[:trigger_id] == nil

      errors =
        InvocationReason.changeset(%InvocationReason{}, %{type: :cron})
        |> errors_on()

      assert errors[:trigger_id] == ["can't be blank"]

      errors =
        InvocationReason.changeset(%InvocationReason{}, %{
          type: :cron,
          trigger_id: "trigger"
        })
        |> errors_on()

      assert errors[:trigger_id] == nil
    end

    test ":manual must have an associated user" do
      errors =
        InvocationReason.changeset(%InvocationReason{}, %{type: :manual})
        |> errors_on()

      assert errors[:user_id] == ["can't be blank"]
    end

    test ":retry must have an associated user" do
      errors =
        InvocationReason.changeset(%InvocationReason{}, %{type: :retry})
        |> errors_on()

      assert errors[:user_id] == ["can't be blank"]
    end
  end
end
