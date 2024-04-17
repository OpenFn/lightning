defmodule Lightning.Workflows.WorkflowUsageLimiter do
  @moduledoc false
  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Workflows.Workflow
  alias Lightning.Services.UsageLimiter

  @spec limit_workflow_activation(Ecto.Changeset.t(Workflow.t())) ::
          :ok | UsageLimiting.error()
  def limit_workflow_activation(workflow_changeset) do
    if Workflow.workflow_activated?(workflow_changeset) do
      UsageLimiter.limit_action(
        %Action{type: :activate_workflow},
        %Context{
          project_id: Ecto.Changeset.get_field(workflow_changeset, :project_id)
        }
      )
    else
      :ok
    end
  end
end
