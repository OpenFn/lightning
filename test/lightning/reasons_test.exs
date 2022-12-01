defmodule Lightning.InvocationReasonsTest do
  use Oban.Testing, repo: Lightning.Repo
  use Lightning.DataCase, async: true

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  import Lightning.AccountsFixtures

  alias Lightning.InvocationReasons
  alias Lightning.InvocationReason

  describe "create_reason/1" do
    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               InvocationReasons.create_reason(%{type: nil})
    end

    test "with valid data creates a reason" do
      valid_attrs = %{
        type: :webhook,
        user_id: user_fixture().id,
        run_id: run_fixture().id,
        dataclip_id: dataclip_fixture().id,
        trigger_id: job_fixture().trigger.id
      }

      assert {:ok, %InvocationReason{}} =
               InvocationReasons.create_reason(valid_attrs)
    end
  end

  describe "build/2" do
    test "with trigger of type :webhook or :cron returns a valid reason" do
      dataclip = dataclip_fixture()

      assert %Ecto.Changeset{valid?: true} =
               InvocationReasons.build(
                 job_fixture(trigger: %{type: :webhook}).trigger,
                 dataclip
               )

      assert %Ecto.Changeset{valid?: true} =
               InvocationReasons.build(
                 job_fixture(trigger: %{type: :cron}).trigger,
                 dataclip
               )

      errors =
        InvocationReasons.build(
          job_fixture(
            trigger: %{
              type: :on_job_success,
              upstream_job_id: job_fixture().id
            }
          ).trigger,
          dataclip
        )
        |> errors_on()

      assert {:type, ["is invalid"]} in errors
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
