defmodule Lightning.Workflows.Audit do
  @moduledoc """
  Generate Audit changesets for selected changes to workflows.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "workflow",
    events: [
      "snapshot_created"
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
end
