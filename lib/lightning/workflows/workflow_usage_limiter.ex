defmodule Lightning.Workflows.WorkflowUsageLimiter do
  @moduledoc false
  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Projects.Project
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Workflow

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

  @spec limit_workflow_creation(project :: Project.t()) ::
          :ok | UsageLimiting.error()
  def limit_workflow_creation(project) do
    %Workflow{project_id: project.id}
    |> Workflow.changeset(%{triggers: [%{enabled: true}]})
    |> limit_workflow_activation()
  end
end
