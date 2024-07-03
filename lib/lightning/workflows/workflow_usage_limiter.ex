defmodule Lightning.Workflows.WorkflowUsageLimiter do
  @moduledoc false
  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Projects.Project
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Workflow

  @spec limit_workflows_activation(Project.t(), [
          Ecto.Changeset.t(Workflow.t()),
          ...
        ]) ::
          :ok | UsageLimiting.error()
  def limit_workflows_activation(project, workflow_changesets) do
    activated_workflows_count =
      Enum.count(workflow_changesets, &Workflow.workflow_activated?/1)

    if activated_workflows_count > 0 do
      limit_action(project.id, activated_workflows_count)
    else
      :ok
    end
  end

  @spec limit_workflow_activation(Ecto.Changeset.t(Workflow.t())) ::
          :ok | UsageLimiting.error()
  def limit_workflow_activation(workflow_changeset) do
    if Workflow.workflow_activated?(workflow_changeset) do
      workflow_changeset
      |> Ecto.Changeset.get_field(:project_id)
      |> limit_action()
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

  defp limit_action(project_id, count \\ 1) do
    UsageLimiter.limit_action(
      %Action{type: :activate_workflow, amount: count},
      %Context{
        project_id: project_id
      }
    )
  end
end
