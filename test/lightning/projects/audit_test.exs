defmodule Lightning.Projects.AuditTest do
  use Lightning.DataCase, async: true

  alias Ecto.Multi

  alias Lightning.Projects.Audit
  alias Lightning.Projects.Project

  setup do
    project =
      insert(
        :project,
        dataclip_retention_period: 14,
        history_retention_period: 90,
        retention_policy: :retain_all
      )

    user = insert(:user)

    %{project: project, user: user}
  end

  describe ".history_retention_auditing_operation" do
    test "if history retention period is updated, returns multi for update", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      changes = %{
        project: %{
          dataclip_retention_period: 7,
          history_retention_period: 30,
          retention_policy: :retain_with_errors
        }
      }

      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      original_changeset = project |> Project.changeset(attrs)

      [audit_history_retention: {:insert, changeset, []}] =
        Audit.history_retention_auditing_operation(
          changes,
          original_changeset,
          user
        )
        |> Multi.to_list()

      assert %{
               changes: %{
                 event: "history_retention_period_updated",
                 item_type: "project",
                 item_id: ^project_id,
                 actor_id: ^user_id,
                 changes: %{
                   changes: audit_changes
                 }
               },
               valid?: true
             } = changeset

      assert audit_changes == %{
               before: %{history_retention_period: 90},
               after: %{history_retention_period: 30}
             }
    end

    test "if history retention period is unchanged, returns empty multi", %{
      project: project,
      user: user
    } do
      changes = %{
        project: %{
          dataclip_retention_period: 7,
          history_retention_period: 90,
          retention_policy: :retain_with_errors
        }
      }

      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 90,
        retention_policy: :retain_with_errors
      }

      original_changeset = project |> Project.changeset(attrs)

      updated_multi =
        Audit.history_retention_auditing_operation(
          changes,
          original_changeset,
          user
        )
        |> Multi.to_list()

      assert updated_multi == []
    end

    test "if history retention period is not present, returns empty multi", %{
      project: project,
      user: user
    } do
      changes = %{
        project: %{
          dataclip_retention_period: 7,
          retention_policy: :retain_with_errors
        }
      }

      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 90,
        retention_policy: :retain_with_errors
      }

      original_changeset = project |> Project.changeset(attrs)

      updated_multi =
        Audit.history_retention_auditing_operation(
          changes,
          original_changeset,
          user
        )
        |> Multi.to_list()

      assert updated_multi == []
    end
  end

  describe ".dataclip_retention_auditing_operation" do
    test "if dataclip retention period is updated, returns multi for update", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      changes = %{
        project: %{
          dataclip_retention_period: 7,
          history_retention_period: 30,
          retention_policy: :retain_with_errors
        }
      }

      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      original_changeset = project |> Project.changeset(attrs)

      [audit_dataclip_retention: {:insert, changeset, []}] =
        Audit.dataclip_retention_auditing_operation(
          changes,
          original_changeset,
          user
        )
        |> Multi.to_list()

      assert %{
               changes: %{
                 event: "dataclip_retention_period_updated",
                 item_type: "project",
                 item_id: ^project_id,
                 actor_id: ^user_id,
                 changes: %{
                   changes: audit_changes
                 }
               },
               valid?: true
             } = changeset

      assert audit_changes == %{
               before: %{dataclip_retention_period: 14},
               after: %{dataclip_retention_period: 7}
             }
    end

    test "if dataclip retention period is unchanged, returns empty multi", %{
      project: project,
      user: user
    } do
      changes = %{
        project: %{
          dataclip_retention_period: 14,
          history_retention_period: 30,
          retention_policy: :retain_with_errors
        }
      }

      attrs = %{
        dataclip_retention_period: 14,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      original_changeset = project |> Project.changeset(attrs)

      updated_multi =
        Audit.dataclip_retention_auditing_operation(
          changes,
          original_changeset,
          user
        )
        |> Multi.to_list()

      assert updated_multi == []
    end

    test "if dataclip retention period is absent, returns empty multi", %{
      project: project,
      user: user
    } do
      changes = %{
        project: %{
          history_retention_period: 30,
          retention_policy: :retain_with_errors
        }
      }

      attrs = %{
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      original_changeset = project |> Project.changeset(attrs)

      updated_multi =
        Audit.dataclip_retention_auditing_operation(
          changes,
          original_changeset,
          user
        )
        |> Multi.to_list()

      assert updated_multi == []
    end
  end
end
