defmodule Lightning.Workflows.TriggerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Trigger

  describe "jsonb-bound trigger fields" do
    test "a NUL in a comment is a changeset error" do
      # Both are copied into the workflow_snapshots.triggers jsonb (#4893).
      for {field, message} <- [
            {:comment, "comment can't contain a null byte"}
          ] do
        changeset =
          Trigger.changeset(
            %Trigger{},
            Map.put(%{type: :webhook}, field, "bad\u{0000}value")
          )

        assert errors_on(changeset)[field] == [message],
               "expected #{field} to reject a null byte"
      end
    end

    test "an over-long comment is a changeset error, not a 22001" do
      # Both columns are varchar(255) and neither had a length guard, so a 300
      # character comment gave valid? == true and then raised on insert.
      for {field, message} <- [
            {:comment, "comment is too long, please use a shorter one"}
          ] do
        changeset =
          Trigger.changeset(
            %Trigger{},
            Map.put(%{type: :webhook}, field, String.duplicate("a", 300))
          )

        assert errors_on(changeset)[field] == [message],
               "expected #{field} to reject an over-long value"
      end
    end

    test "an over-long cron_expression is a changeset error, not a 22001" do
      # The third field on the same cast/3, same varchar(255), and the only one
      # that had no guard. Crontab parses this happily, so the changeset said
      # valid? and the insert raised. Reachable through POST /api/provision.
      expression = "*/1 " <> String.duplicate("1,", 130) <> "1 * * *"
      assert String.length(expression) > 255

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: expression
        })

      assert errors_on(changeset)[:cron_expression] == [
               "cron expression is too long, please use a shorter one"
             ]
    end

    test "an ordinary cron_expression is untouched" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "0 23 * * *"
        })

      refute errors_on(changeset)[:cron_expression]
    end

    test "a comment short in graphemes but too wide for the column is rejected" do
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"

      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          comment: String.duplicate(family, 200)
        })

      assert errors_on(changeset)[:comment] == [
               "comment is too long, please use a shorter one"
             ]
    end

    test "a comment may hold newlines and tabs" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          comment: "line one\nline\ttwo"
        })

      refute errors_on(changeset)[:comment]
    end
  end

  describe "synchronous?/1" do
    test "returns true for :after_completion" do
      assert Trigger.synchronous?(%Trigger{webhook_reply: :after_completion})
    end

    test "returns false for :custom, which has no response publisher" do
      refute Trigger.synchronous?(%Trigger{webhook_reply: :custom})
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
