defmodule LightningWeb.WorkflowLive.Helpers do
  @moduledoc """
  Helper functions for the Workflow LiveViews.
  """

  alias Lightning.Repo

  alias Lightning.Workflows
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders

  @spec save_and_run(
          Ecto.Changeset.t(Workflows.Workflow.t()),
          map(),
          selected_job: map(),
          created_by: map(),
          project: map()
        ) ::
          {:ok,
           %{
             workorder: WorkOrder.t(),
             workflow: Workflows.Workflow.t()
           }}
          | {:error, Ecto.Changeset.t(Workflows.Workflow.t())}
          | {:error, Ecto.Changeset.t(WorkOrders.Manual.t())}
  def save_and_run(workflow_changeset, params, opts) do
    Lightning.Repo.transact(fn ->
      with {:ok, workflow} <- save_workflow(workflow_changeset),
           {:ok, manual} <- build_manual_workorder(params, workflow, opts),
           {:ok, workorder} <- WorkOrders.create_for(manual) do
        {:ok, %{workorder: workorder, workflow: workflow}}
      end
    end)
  end

  defp build_manual_workorder(params, workflow, opts) do
    {selected_job, opts} = Keyword.pop!(opts, :selected_job)

    opts =
      Keyword.merge(opts, job: Repo.reload(selected_job), workflow: workflow)

    params
    |> WorkOrders.Manual.new(opts)
    |> Ecto.Changeset.apply_action(:validate)
  end

  defp save_workflow(changeset) do
    Repo.insert_or_update(changeset)
  end
end
