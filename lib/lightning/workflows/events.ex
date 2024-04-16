defmodule Lightning.Workflows.Events do
  @moduledoc false

  defmodule WorkflowUpdated do
    @moduledoc false
    defstruct workflow: nil
  end

  def workflow_updated(workflow) do
    Lightning.broadcast(
      topic(workflow.project_id),
      %WorkflowUpdated{workflow: workflow}
    )
  end

  def subscribe(project_id) do
    Lightning.subscribe(topic(project_id))
  end

  defp topic(project_id), do: "workflow_events:#{project_id}"
end
