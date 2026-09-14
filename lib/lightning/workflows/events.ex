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

  @doc """
  Subscribes to the workflow events of a single project.

  This is a high-traffic topic: `WorkflowUpdated` fires on every save in the
  project. Session-teardown events belong on `Lightning.Projects.Events`
  instead, which the same surfaces already subscribe to and which only carries
  events that change what a session may do — see
  `Lightning.Projects.Events.WorkflowDeleted`.
  """
  def subscribe(project_id) do
    Lightning.subscribe(topic(project_id))
  end

  defp topic(project_id), do: "workflow_events:#{project_id}"
end
