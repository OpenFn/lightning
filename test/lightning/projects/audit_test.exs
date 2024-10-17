defmodule Lightning.Projects.AuditTest do
  use Lightning.DataCase

  import ExUnit.CaptureLog
  import Mock

  alias Lightning.Auditing
  alias Lightning.Auditing.Audit.Changes
  alias Lightning.Projects.Audit
  alias Lightning.Projects.Project

  describe "./audit_history_retention_period_updated/3" do
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
               item_id: ^project_id,
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
               item_id: ^project_id,
               actor_id: ^user_id,
               changes: changes
             } = audit_event

      assert changes == %Changes{
               before: %{"history_retention_period" => 90},
               after: %{"history_retention_period" => nil}
             }
    end

    test "does not create event if history retention period is not updated", %{
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

    test "returns the result of saving the event", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 90,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      response =
        project
        |> Audit.audit_history_retention_period_updated(changeset, user)

      assert {:ok, :no_changes} = response

      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      response =
        project
        |> Audit.audit_history_retention_period_updated(changeset, user)

      assert {:ok, %Auditing.Audit{}} = response
    end

    test "logs if there is an error saving the event", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      with_mocks([
        {
          Lightning.Auditing.Audit,
          [:passthrough],
          [
            save: fn _event, _repo ->
              {
                :error,
                %{data: project, changes: %{history_retention_period: 30}}
              }
            end
          ]
        }
      ]) do
        fun = fn ->
          project
          |> Audit.audit_history_retention_period_updated(changeset, user)
        end

        assert capture_log(fun) =~ "Saving audit event"
        assert capture_log(fun) =~ "project_id: \"#{project.id}\""
        assert capture_log(fun) =~ "user_id: \"#{user.id}\""
        assert capture_log(fun) =~ "event: \"history_retention_period_updated\""
        assert capture_log(fun) =~ "before_value: 90"
        assert capture_log(fun) =~ "after_value: 30"
      end
    end

    test "it notifies Sentry if there is an error saving the event", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      message = "Error saving audit event"

      extra = %{
        project_id: project.id,
        user_id: user.id,
        event: "history_retention_period_updated",
        before_value: 90,
        after_value: 30
      }

      with_mocks([
        {
          Lightning.Auditing.Audit,
          [:passthrough],
          [
            save: fn _event, _repo ->
              {
                :error,
                %{data: project, changes: %{history_retention_period: 30}}
              }
            end
          ]
        },
        {Sentry, [], [capture_message: fn _data, _extra -> :ok end]}
      ]) do
        project
        |> Audit.audit_history_retention_period_updated(changeset, user)

        assert_called(Sentry.capture_message(message, extra: extra))
      end
    end
  end

  describe "./audit_dataclip_retention_period_updated/3" do
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

    test "creates an event if the dataclip retention period is updated", %{
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
      |> Audit.audit_dataclip_retention_period_updated(changeset, user)

      audit_event = Auditing.Audit |> Repo.one!()

      assert %{
               event: "dataclip_retention_period_updated",
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^user_id,
               changes: changes
             } = audit_event

      assert changes == %Changes{
               before: %{"dataclip_retention_period" => 14},
               after: %{"dataclip_retention_period" => 7}
             }
    end

    test "creates an event if the dataclip retention period is set to nil", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      attrs = %{
        dataclip_retention_period: nil,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      project
      |> Audit.audit_dataclip_retention_period_updated(changeset, user)

      audit_event = Auditing.Audit |> Repo.one!()

      assert %{
               event: "dataclip_retention_period_updated",
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^user_id,
               changes: changes
             } = audit_event

      assert changes == %Changes{
               before: %{"dataclip_retention_period" => 14},
               after: %{"dataclip_retention_period" => nil}
             }
    end

    test "does not create event if dataclip retention period is not updated", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 14,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      project
      |> Audit.audit_dataclip_retention_period_updated(changeset, user)

      assert Auditing.Audit |> Repo.one() == nil
    end

    test "returns the result of saving the event", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 14,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      response =
        project
        |> Audit.audit_dataclip_retention_period_updated(changeset, user)

      assert {:ok, :no_changes} = response

      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      response =
        project
        |> Audit.audit_dataclip_retention_period_updated(changeset, user)

      assert {:ok, %Auditing.Audit{}} = response
    end

    test "logs if there is an error saving the event", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      with_mocks([
        {
          Lightning.Auditing.Audit,
          [:passthrough],
          [
            save: fn _event, _repo ->
              {
                :error,
                %{data: project, changes: %{dataclip_retention_period: 7}}
              }
            end
          ]
        }
      ]) do
        fun = fn ->
          project
          |> Audit.audit_dataclip_retention_period_updated(changeset, user)
        end

        assert capture_log(fun) =~ "Saving audit event"
        assert capture_log(fun) =~ "project_id: \"#{project.id}\""
        assert capture_log(fun) =~ "user_id: \"#{user.id}\""
        assert capture_log(fun) =~ "event: \"dataclip_retention_period_updated\""
        assert capture_log(fun) =~ "before_value: 14"
        assert capture_log(fun) =~ "after_value: 7"
      end
    end

    test "it notifies Sentry if there is an error saving the event", %{
      project: project,
      user: user
    } do
      attrs = %{
        dataclip_retention_period: 7,
        history_retention_period: 30,
        retention_policy: :retain_with_errors
      }

      changeset = project |> Project.changeset(attrs)

      message = "Error saving audit event"

      extra = %{
        project_id: project.id,
        user_id: user.id,
        event: "dataclip_retention_period_updated",
        before_value: 14,
        after_value: 7
      }

      with_mocks([
        {
          Lightning.Auditing.Audit,
          [:passthrough],
          [
            save: fn _event, _repo ->
              {
                :error,
                %{data: project, changes: %{dataclip_retention_period: 7}}
              }
            end
          ]
        },
        {Sentry, [], [capture_message: fn _data, _extra -> :ok end]}
      ]) do
        project
        |> Audit.audit_dataclip_retention_period_updated(changeset, user)

        assert_called(Sentry.capture_message(message, extra: extra))
      end
    end
  end
end
