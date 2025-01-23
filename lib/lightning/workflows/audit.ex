defmodule Lightning.Workflows.Audit do
  @moduledoc """
  Generate Audit changesets for selected changes to workflows.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "workflow",
    events: [
      "snapshot_created",
      "enabled",
      "disabled",
      "deleted_by_provisioner",
      "inserted_by_provisioner",
      "updated_by_provisioner"
    ]

  def snapshot_created(workflow_id, snapshot_id, actor) do
    event(
      "snapshot_created",
      workflow_id,
      actor,
      %{
        after: %{snapshot_id: snapshot_id}
      }
    )
  end

  def workflow_state_changed(event, workflow_id, actor, changes) do
    event(
      event,
      workflow_id,
      actor,
      changes
    )
  end

  def provisioner_event(action, workflow_id, actor) do
    event(
      "#{past_tense(action)}_by_provisioner",
      workflow_id,
      actor,
      %{}
    )
  end

  def past_tense(action) do
    if action == :insert, do: "inserted", else: "#{action}d"
  end
end
