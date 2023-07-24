defmodule Lightning.InvocationReasonsTest do
  use Lightning.DataCase, async: true

  import Lightning.InvocationFixtures
  import Lightning.AccountsFixtures
  import Lightning.Factories

  alias Lightning.InvocationReasons
  alias Lightning.InvocationReason

  describe "create_reason/1" do
    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               InvocationReasons.create_reason(%{type: nil})
    end

    test "with valid data creates a reason" do
      trigger = insert(:trigger, %{type: :webhook})

      valid_attrs = %{
        type: :webhook,
        user_id: user_fixture().id,
        run_id: run_fixture().id,
        dataclip_id: dataclip_fixture().id,
        trigger_id: trigger.id
      }

      assert {:ok, %InvocationReason{}} =
               InvocationReasons.create_reason(valid_attrs)
    end
  end

  describe "build/2" do
    test "with trigger of type :webhook or :cron returns a valid reason" do
      trigger = insert(:trigger, %{type: :webhook})
      cron_trigger = insert(:trigger, %{type: :cron})
      dataclip = dataclip_fixture()

      assert %Ecto.Changeset{valid?: true} =
               InvocationReasons.build(
                 trigger,
                 dataclip
               )

      assert %Ecto.Changeset{valid?: true} =
               InvocationReasons.build(
                 cron_trigger,
                 dataclip
               )
    end

    test "with :manual" do
      dataclip = dataclip_fixture()

      assert %Ecto.Changeset{valid?: true} =
               InvocationReasons.build(:manual, %{
                 user: user_fixture(),
                 dataclip: dataclip
               })
    end

    test "with :retry" do
      run = run_fixture()

      assert %Ecto.Changeset{valid?: true} =
               InvocationReasons.build(:retry, %{user: user_fixture(), run: run})
    end
  end
end
