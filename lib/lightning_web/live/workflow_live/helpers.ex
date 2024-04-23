defmodule LightningWeb.WorkflowLive.Helpers do
  @moduledoc """
  Helper functions for the Workflow LiveViews.
  """

  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter

  alias Lightning.Workflows
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders

  @spec save_workflow(Ecto.Changeset.t()) ::
          {:ok, Workflows.Workflow.t()}
          | {:error, Ecto.Changeset.t() | UsageLimiting.message()}
  def save_workflow(changeset) do
    case WorkflowUsageLimiter.limit_workflow_activation(changeset) do
      :ok ->
        Workflows.save_workflow(changeset)

      {:error, _reason, message} ->
        {:error, message}
    end
  end

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
             workflow: Workflows.Workflow.t(),
             message: UsageLimiting.message()
           }}
          | {:error, Ecto.Changeset.t(Workflows.Workflow.t())}
          | {:error, Ecto.Changeset.t(WorkOrders.Manual.t())}
          | {:error, UsageLimiting.message()}
  def save_and_run(workflow_changeset, params, opts) do
    Lightning.Repo.transact(fn ->
      %{id: project_id} = Keyword.fetch!(opts, :project)

      case UsageLimiter.limit_action(%Action{type: :new_run}, %Context{
             project_id: project_id
           }) do
        {:error, _reason, message} ->
          {:error, message}

        :ok ->
          with {:ok, workflow} <- Workflows.save_workflow(workflow_changeset),
               {:ok, manual} <- build_manual_workorder(params, workflow, opts),
               {:ok, workorder} <- WorkOrders.create_for(manual) do
            {:ok, %{workorder: workorder, workflow: workflow}}
          end
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
end
