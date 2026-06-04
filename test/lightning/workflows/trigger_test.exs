defmodule Lightning.Workflows.TriggerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.KafkaConfiguration

  describe "synchronous?/1" do
    test "returns true for :after_completion" do
      assert Trigger.synchronous?(%Trigger{webhook_reply: :after_completion})
    end

    test "returns true for :custom" do
      assert Trigger.synchronous?(%Trigger{webhook_reply: :custom})
    end

    test "returns false for :before_start" do
      refute Trigger.synchronous?(%Trigger{webhook_reply: :before_start})
    end

    test "returns false for nil" do
      refute Trigger.synchronous?(%Trigger{webhook_reply: nil})
    end
  end

  describe "changeset/2" do
    test "type must be valid" do
      errors = Trigger.changeset(%Trigger{}, %{type: :foo}) |> errors_on()
      assert errors[:type] == ["is invalid"]

      errors = Trigger.changeset(%Trigger{}, %{type: :webhook}) |> errors_on()
      assert errors[:type] == nil
    end

    test "a malformed workflow_id is a changeset error, not an Ecto.ChangeError on save" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          workflow_id: "__ID_JOB_Fetch__"
        })

      refute changeset.valid?
      assert changeset.errors[:workflow_id] == {"is not a valid UUID", []}
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

    test "allows creation of kafka trigger" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka,
          kafka_configuration: %{
            group_id: "group_id",
            hosts: [
              ["host1", "9092"],
              ["host2", "9093"]
            ],
            hosts_string: "host1:9092, host2:9093",
            initial_offset_reset_policy: "earliest",
            password: "password",
            sasl: "plain",
            ssl: true,
            topics: ["foo", "bar"],
            topics_string: "foo, bar",
            username: "username"
          }
        })

      assert %{valid?: true} = changeset
    end

    test "removes cron expression job when type is :kafka" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka,
          cron_expression: "* * * *"
        })

      assert get_field(changeset, :cron_expression) == nil

      changeset =
        Trigger.changeset(
          %Trigger{type: :cron, cron_expression: "* * * *"},
          %{
            type: :kafka
          }
        )

      assert get_field(changeset, :cron_expression) == nil
    end

    test "is invalid if type is :kafka but kafka_configuration is not set" do
      errors =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka
        })
        |> errors_on()

      assert errors[:kafka_configuration] == ["can't be blank"]
    end

    test "removes kafka config when type is :webhook" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          kafka_configuration: %{a: :b}
        })

      assert get_field(changeset, :kafka_configuration) == nil

      changeset =
        Trigger.changeset(
          %Trigger{
            type: :kafka,
            kafka_configuration: %KafkaConfiguration{group_id: "foo"}
          },
          %{
            type: :webhook
          }
        )

      assert get_field(changeset, :kafka_configuration) == nil
    end

    test "removes kafka config when type is :cron" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          kafka_configuration: %{a: :b}
        })

      assert get_field(changeset, :kafka_configuration) == nil

      changeset =
        Trigger.changeset(
          %Trigger{
            type: :kafka,
            kafka_configuration: %KafkaConfiguration{group_id: "foo"}
          },
          %{
            type: :cron
          }
        )

      assert get_field(changeset, :kafka_configuration) == nil
    end

    test "sets webhook_reply to nil when type is :cron" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          webhook_reply: :before_start
        })

      assert get_field(changeset, :webhook_reply) == nil

      # Also when converting from webhook to cron
      changeset =
        Trigger.changeset(
          %Trigger{type: :webhook, webhook_reply: :after_completion},
          %{type: :cron}
        )

      assert get_field(changeset, :webhook_reply) == nil
    end

    test "sets webhook_reply to nil when type is :kafka" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka,
          webhook_reply: :custom,
          kafka_configuration: %{
            group_id: "group_id",
            hosts: [["host1", "9092"]],
            hosts_string: "host1:9092",
            initial_offset_reset_policy: "earliest",
            sasl: "plain",
            ssl: true,
            topics: ["foo"],
            topics_string: "foo"
          }
        })

      assert get_field(changeset, :webhook_reply) == nil

      # Also when converting from webhook to kafka
      changeset =
        Trigger.changeset(
          %Trigger{type: :webhook, webhook_reply: :before_start},
          %{
            type: :kafka,
            kafka_configuration: %{
              group_id: "group_id",
              hosts: [["host1", "9092"]],
              hosts_string: "host1:9092",
              initial_offset_reset_policy: "earliest",
              sasl: "plain",
              ssl: true,
              topics: ["foo"],
              topics_string: "foo"
            }
          }
        )

      assert get_field(changeset, :webhook_reply) == nil
    end

    test "cron_cursor_job_id is cast for cron triggers" do
      job_id = Ecto.UUID.generate()

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "* * * * *",
          cron_cursor_job_id: job_id
        })

      assert get_field(changeset, :cron_cursor_job_id) == job_id
    end

    test "cron_cursor_job_id is cleared when type changes to :webhook" do
      job_id = Ecto.UUID.generate()

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          cron_cursor_job_id: job_id
        })

      assert get_field(changeset, :cron_cursor_job_id) == nil

      # Also when converting from cron to webhook
      changeset =
        Trigger.changeset(
          %Trigger{
            type: :cron,
            cron_expression: "* * * * *",
            cron_cursor_job_id: job_id
          },
          %{type: :webhook}
        )

      assert get_field(changeset, :cron_cursor_job_id) == nil
    end

    test "cron_cursor_job_id is cleared when type changes to :kafka" do
      job_id = Ecto.UUID.generate()

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :kafka,
          cron_cursor_job_id: job_id,
          kafka_configuration: %{
            group_id: "group_id",
            hosts: [["host1", "9092"]],
            hosts_string: "host1:9092",
            initial_offset_reset_policy: "earliest",
            sasl: "plain",
            ssl: true,
            topics: ["foo"],
            topics_string: "foo"
          }
        })

      assert get_field(changeset, :cron_cursor_job_id) == nil

      # Also when converting from cron to kafka
      changeset =
        Trigger.changeset(
          %Trigger{
            type: :cron,
            cron_expression: "* * * * *",
            cron_cursor_job_id: job_id
          },
          %{
            type: :kafka,
            kafka_configuration: %{
              group_id: "group_id",
              hosts: [["host1", "9092"]],
              hosts_string: "host1:9092",
              initial_offset_reset_policy: "earliest",
              sasl: "plain",
              ssl: true,
              topics: ["foo"],
              topics_string: "foo"
            }
          }
        )

      assert get_field(changeset, :cron_cursor_job_id) == nil
    end

    test "a malformed cron_cursor_job_id is a changeset error, not an Ecto.ChangeError on save" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "* * * * *",
          cron_cursor_job_id: "__ID_JOB_Envoyer-dans-DHIS2__"
        })

      refute changeset.valid?

      assert changeset.errors[:cron_cursor_job_id] ==
               {"is not a valid UUID", []}
    end

    test "cron_cursor_job_id pointing at a non-existent job is a changeset error, not a raise" do
      workflow = insert(:workflow)

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          cron_expression: "* * * * *"
        )

      changeset =
        Trigger.changeset(trigger, %{cron_cursor_job_id: Ecto.UUID.generate()})

      assert {:error, changeset} = Lightning.Repo.update(changeset)

      assert {"cursor job doesn't exist, or is not in the same workflow", _} =
               changeset.errors[:cron_cursor_job_id]
    end

    test "cron_cursor_job_id pointing at a job in another workflow is rejected" do
      workflow_a = insert(:workflow)
      workflow_b = insert(:workflow)
      foreign_job = insert(:job, workflow: workflow_b)

      trigger =
        insert(:trigger,
          workflow: workflow_a,
          type: :cron,
          cron_expression: "* * * * *"
        )

      assert {:error, changeset} =
               trigger
               |> Trigger.changeset(%{cron_cursor_job_id: foreign_job.id})
               |> Lightning.Repo.update()

      assert {"cursor job doesn't exist, or is not in the same workflow", _} =
               changeset.errors[:cron_cursor_job_id]
    end

    test "cron_cursor_job_id pointing at a job in the SAME workflow is accepted" do
      workflow = insert(:workflow)
      job = insert(:job, workflow: workflow)

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          cron_expression: "* * * * *"
        )

      assert {:ok, updated} =
               trigger
               |> Trigger.changeset(%{cron_cursor_job_id: job.id})
               |> Lightning.Repo.update()

      assert updated.cron_cursor_job_id == job.id
    end

    test "deleting the cursor job nulls only the cursor, not the workflow link" do
      workflow = insert(:workflow)
      job = insert(:job, workflow: workflow)

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :cron,
          cron_expression: "* * * * *"
        )
        |> Trigger.changeset(%{cron_cursor_job_id: job.id})
        |> Lightning.Repo.update!()

      Lightning.Repo.delete!(job)

      reloaded = Lightning.Repo.reload!(trigger)
      assert reloaded.cron_cursor_job_id == nil
      assert reloaded.workflow_id == workflow.id
    end

    test "allows webhook_reply to be set for webhook triggers" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          webhook_reply: :after_completion
        })

      assert get_field(changeset, :webhook_reply) == :after_completion

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          webhook_reply: :custom
        })

      assert get_field(changeset, :webhook_reply) == :custom
    end
  end
end
