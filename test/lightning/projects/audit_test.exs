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

  describe "derive_events" do
    test "if history retention period is updated, returns multi for update", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      attrs = %{
        # dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      [{"audit_history_retention_period", {:insert, changeset, []}}] =
        Audit.derive_events(
          Multi.new(),
          Project.changeset(project, attrs),
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

    test "if the fields we are tracking are unchanged, returns empty multi", %{
      project: project,
      user: user
    } do
      assert [] =
               Audit.derive_events(
                 Multi.new(),
                 project
                 |> Project.changeset(%{retention_policy: :retain_with_errors}),
                 user
               )
               |> Multi.to_list()
    end

    test "if dataclip retention period is updated, returns multi for update", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      attrs = %{
        dataclip_retention_period: 7
      }

      [{"audit_dataclip_retention_period", {:insert, changeset, []}}] =
        Audit.derive_events(
          Multi.new(),
          Project.changeset(project, attrs),
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

    test "if more than one field we are tracking is changed", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 14,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      events_multi =
        Audit.derive_events(
          Multi.new(),
          Project.changeset(project, attrs),
          user
        )
        |> Multi.to_list()

      for {name, change} <- events_multi do
        assert name in [
                 "audit_dataclip_retention_period",
                 "audit_history_retention_period"
               ]

        assert {:insert, _, []} = change
      end
    end
  end
end
