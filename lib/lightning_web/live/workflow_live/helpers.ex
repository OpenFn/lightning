defmodule LightningWeb.WorkflowLive.Helpers do
  @moduledoc """
  Helper functions for the Workflow LiveViews.
  """

  alias Lightning.Repo

  alias Lightning.Workflows
  alias Lightning.WorkOrders
  alias Lightning.WorkOrder

  @spec save_and_run(
          Ecto.Changeset.t(Workflows.Workflow.t()),
          Ecto.Changeset.t(WorkOrders.Manual.t())
        ) ::
          {:ok,
           %{
             workorder: WorkOrder.t(),
             workflow: Workflows.Workflow.t()
           }}
          | {:error, Ecto.Changeset.t(Workflows.Workflow.t())}
          | {:error, Ecto.Changeset.t(WorkOrders.Manual.t())}
  def save_and_run(workflow_changeset, manual_workorder_changeset) do
    Lightning.Repo.transact(fn ->
      with {:ok, workflow} <- save_workflow(workflow_changeset),
           {:ok, manual} <-
             Ecto.Changeset.apply_action(manual_workorder_changeset, :validate),
           {:ok, workorder} <- WorkOrders.create_for(manual) do
        {:ok, %{workorder: workorder, workflow: workflow}}
      end
    end)
  end

  @spec save_workflow(Ecto.Changeset.t(Workflows.Workflow.t())) ::
          {:ok, Workflows.Workflow.t()}
          | {:error, Ecto.Changeset.t(Workflows.Workflow.t())}
  def save_workflow(changeset) do
    Repo.insert_or_update(changeset)
  end
end
