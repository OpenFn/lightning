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

    test "must have an upstream job when type is :on_job_x" do
      for type <- [:on_job_success, :on_job_failure] do
        # errors = Trigger.changeset(%Trigger{}, %{type: type}) |> errors_on()

        # assert errors[:upstream_job_id] == ["can't be blank"]
        # assert errors[:type] == nil

        job = job_fixture()

        errors =
          Trigger.changeset(%Trigger{}, %{
            type: type,
            upstream_job_id: job.id
          })
          |> errors_on()

        assert errors[:upstream_job_id] == nil
        assert errors[:type] == nil
      end
    end

    test "must raise an error when cron expression is invalid" do
      errors =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "this_is_not_a_cron_valid_cron_expression"
        })
        |> errors_on()

      assert errors[:cron_expression] == [
               "Can't parse this_is_not_a_cron_valid_cron_expression as minute."
             ]
    end

    test "must raise no error when cron expression is valid" do
      errors =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "* * * *"
        })
        |> errors_on()

      assert errors[:cron_expression] == nil
    end

    test "removes any upstream job when type is :webhook" do
      job = job_fixture()

      changeset =
        Trigger.changeset(%Trigger{}, %{type: :webhook, upstream_job_id: job.id})

      assert get_field(changeset, :upstream_job_id) == nil

      changeset =
        Trigger.changeset(
          %Trigger{type: :on_job_success, upstream_job_id: job.id},
          %{
            type: :webhook
          }
        )

      assert get_field(changeset, :upstream_job_id) == nil
    end

    test "removes cron expression job when type is :webhook" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          cron_expression: "* * * *"
        })

      assert get_field(changeset, :cron_expression) == nil

      changeset =
        Trigger.changeset(
          %Trigger{type: :cron, cron_expression: "* * * *"},
          %{
            type: :webhook
          }
        )

      assert get_field(changeset, :cron_expression) == nil
    end

    test "removes cron expression job when type is :on_job_x" do
      for type <- [:on_job_success, :on_job_failure] do
        changeset =
          Trigger.changeset(%Trigger{}, %{
            type: type,
            cron_expression: "* * * *"
          })

        assert get_field(changeset, :cron_expression) == nil

        changeset =
          Trigger.changeset(
            %Trigger{type: :cron, cron_expression: "* * * *"},
            %{
              type: type
            }
          )

        assert get_field(changeset, :cron_expression) == nil
      end
    end

    test "removes any upstream job when type is :cron" do
      job = job_fixture()

      changeset =
        Trigger.changeset(%Trigger{}, %{type: :cron, upstream_job_id: job.id})

      assert get_field(changeset, :upstream_job_id) == nil

      changeset =
        Trigger.changeset(
          %Trigger{type: :on_job_success, upstream_job_id: job.id},
          %{
            type: :cron
          }
        )

      assert get_field(changeset, :upstream_job_id) == nil
    end
  end
end
