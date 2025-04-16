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
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders

  def subscribe_to_params_update(socket_id) do
    Lightning.subscribe(socket_id)
  end

  def broadcast_updated_params(socket, params) do
    Lightning.local_broadcast(socket.id, {:updated_params, params})
  end

  @spec save_workflow(Ecto.Changeset.t(), struct()) ::
          {:ok, Workflows.Workflow.t()}
          | {:error,
             Ecto.Changeset.t() | UsageLimiting.message() | :workflow_deleted}
  def save_workflow(changeset, actor) do
    case WorkflowUsageLimiter.limit_workflow_activation(changeset) do
      :ok ->
        Workflows.save_workflow(changeset, actor)

      {:error, _reason, message} ->
        {:error, message}
    end
  end

  @spec run_workflow(
          Ecto.Changeset.t(Workflows.Workflow.t()) | Workflows.Workflow.t(),
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
          | {:error, :workflow_deleted}
  def run_workflow(workflow_or_changeset, params, opts) do
    Lightning.Repo.transact(fn ->
      %{id: project_id} = Keyword.fetch!(opts, :project)
      actor = Keyword.fetch!(opts, :created_by)

      case UsageLimiter.limit_action(%Action{type: :new_run}, %Context{
             project_id: project_id
           }) do
        {:error, _reason, message} ->
          {:error, message}

        :ok ->
          with {:ok, workflow} <-
                 maybe_save_workflow(workflow_or_changeset, actor),
               {:ok, manual} <- build_manual_workorder(params, workflow, opts),
               {:ok, workorder} <- WorkOrders.create_for(manual) do
            {:ok, %{workorder: workorder, workflow: workflow}}
          end
      end
    end)
  end

  defp maybe_save_workflow(%Ecto.Changeset{} = changeset, actor) do
    Workflows.save_workflow(changeset, actor)
  end

  defp maybe_save_workflow(%Workflow{} = workflow, _actor) do
    {:ok, workflow}
  end

  defp build_manual_workorder(params, workflow, opts) do
    {selected_job, opts} = Keyword.pop!(opts, :selected_job)

    opts =
      Keyword.merge(opts, job: Repo.reload(selected_job), workflow: workflow)

    params
    |> WorkOrders.Manual.new(opts)
    |> Ecto.Changeset.apply_action(:validate)
  end

  @doc """
  Determines if a workflow is enabled based on its triggers.
  Accepts either a Workflow struct or an Ecto.Changeset.
  """
  def workflow_enabled?(%Workflow{} = workflow) do
    Enum.all?(workflow.triggers, & &1.enabled)
  end

  def workflow_enabled?(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.get_field(changeset, :triggers)
    |> Enum.all?(&trigger_enabled?/1)
  end

  @doc """
  Generates a tooltip describing the workflow's state.
  Accepts either a Workflow struct or an Ecto.Changeset.
  """
  def workflow_state_tooltip(%Workflow{triggers: triggers}) do
    generate_tooltip(triggers, Enum.all?(triggers, & &1.enabled))
  end

  def workflow_state_tooltip(%Ecto.Changeset{} = changeset) do
    triggers = Ecto.Changeset.fetch_field!(changeset, :triggers)
    generate_tooltip(triggers, Enum.all?(triggers, & &1.enabled))
  end

  defp trigger_enabled?(trigger), do: trigger.enabled

  defp generate_tooltip(triggers, all_enabled) do
    case {all_enabled, triggers} do
      {_, []} ->
        "This workflow is inactive (no triggers configured)"

      {true, [first_trigger | _]} ->
        "This workflow is active (#{first_trigger.type} trigger enabled)"

      {false, _} ->
        "This workflow is inactive (manual runs only)"
    end
  end
end
