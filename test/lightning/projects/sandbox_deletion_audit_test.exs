defmodule Lightning.Projects.SandboxDeletionAuditTest do
  use Lightning.DataCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Auditing.Audit
  alias Lightning.Projects.Sandboxes

  defp events_on(project_ids) do
    Repo.all(
      from a in Audit,
        where: a.item_id in ^project_ids,
        order_by: a.inserted_at,
        select: {a.item_id, a.event, a.actor_id, a.actor_type, a.changes}
    )
  end

  test "scheduling a sandbox's deletion records one deletion_scheduled event, against the sandbox named and the person" do
    actor = insert(:user)
    root = insert(:project)
    sandbox = insert(:project, parent: root)
    nested = insert(:project, parent: sandbox)
    insert(:project_user, project: sandbox, user: actor, role: :owner)

    {:ok, scheduled} = Sandboxes.schedule_sandbox_deletion(sandbox, actor)

    assert events_on([root.id, sandbox.id, nested.id]) == [
             {sandbox.id, "deletion_scheduled", actor.id, :user,
              %Lightning.Auditing.Audit.Changes{
                before: %{"scheduled_deletion" => nil},
                after: %{
                  "scheduled_deletion" =>
                    DateTime.to_iso8601(scheduled.scheduled_deletion)
                }
              }}
           ]
  end

  test "cancelling a sandbox's deletion records a deletion_cancelled event against the service account" do
    {account, _key} = service_account_with_key()
    date = DateTime.utc_now() |> DateTime.truncate(:second)

    sandbox =
      insert(:project, parent: insert(:project), scheduled_deletion: date)

    assert {:ok, %{scheduled_deletion: nil}} =
             Sandboxes.cancel_scheduled_sandbox_deletion(sandbox, account)

    assert events_on([sandbox.id]) == [
             {sandbox.id, "deletion_cancelled", account.uuid, :service_account,
              %Lightning.Auditing.Audit.Changes{
                before: %{"scheduled_deletion" => DateTime.to_iso8601(date)},
                after: %{"scheduled_deletion" => nil}
              }}
           ]
  end
end
