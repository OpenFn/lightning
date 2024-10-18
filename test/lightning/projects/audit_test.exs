defmodule Lightning.Projects.AuditTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing
  alias Lightning.Auditing.Audit.Changes
  alias Lightning.Projects.Audit
  alias Lightning.Projects.Project

  describe "./audit_history_retention_period_updated/3"  do
    setup do
      project =
        insert(
          :project,
          dataclip_retention_period: 14,
          history_retention_period: 90,
          retention_policy: :retain_all
        )

      user = insert(:user)

      %{
        project: project,
        user: user
      }
    end

    test "creates an event if the history retention period is updated", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      project
      |> Audit.audit_history_retention_period_updated(changeset, user)

      audit_event = Auditing.Audit |> Repo.one!()

      assert %{
        event: "history_retention_period_updated",
        item_type: "project",
        item_id:  ^project_id,
        actor_id: ^user_id,
        changes: changes
      } = audit_event

      assert changes == %Changes{
        before: %{"history_retention_period" => 90},
        after: %{"history_retention_period" => 30}
      }
    end

    test "creates an event if the history retention period is set to nil", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      attrs = %{
        dataclip_retention_period: nil,
        history_retention_period: nil,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      project
      |> Audit.audit_history_retention_period_updated(changeset, user)

      audit_event = Auditing.Audit |> Repo.one!()

      assert %{
        event: "history_retention_period_updated",
        item_type: "project",
        item_id:  ^project_id,
        actor_id: ^user_id,
        changes: changes
      } = audit_event

      assert changes == %Changes{
        before: %{"history_retention_period" => 90},
        after: %{"history_retention_period" => nil}
      }
    end

    test "does not create event if history retention period is updated", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 90,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      project
      |> Audit.audit_history_retention_period_updated(changeset, user)

      assert Auditing.Audit |> Repo.one() == nil
    end
  end
end
