defmodule Lightning.WorkOrderService do
  @moduledoc """
  The WorkOrders context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.{WorkOrder, InvocationReasons, AttemptRun, AttemptService}
  alias Lightning.Invocation.{Dataclip, Run}

  alias Ecto.Multi

  def multi_for(:webhook, job, dataclip_body) do
    Multi.new()
    |> Multi.insert(
      :dataclip,
      Dataclip.new(%{
        type: :http_request,
        body: dataclip_body,
        project_id: job.workflow.project_id
      })
    )
    |> Multi.insert(:reason, fn %{dataclip: dataclip} ->
      InvocationReasons.build(job.trigger, dataclip)
    end)
    |> Multi.insert(:work_order, fn %{reason: reason} ->
      build(job.workflow, reason)
    end)
    |> Multi.insert(:attempt, fn %{work_order: work_order, reason: reason} ->
      AttemptService.build_attempt(work_order, reason)
    end)
    |> Multi.insert(:attempt_run, fn %{
                                       attempt: attempt,
                                       dataclip: dataclip
                                     } ->
      AttemptRun.new()
      |> Ecto.Changeset.put_assoc(:attempt, attempt)
      |> Ecto.Changeset.put_assoc(
        :run,
        Run.new(%{
          job_id: job.id,
          input_dataclip_id: dataclip.id
        })
      )
    end)
  end

  def multi_for(:cron, job, dataclip) do
    Multi.new()
    |> Multi.put(:dataclip, dataclip)
    |> Multi.insert(:reason, fn %{dataclip: dataclip} ->
      InvocationReasons.build(job.trigger, dataclip)
    end)
    |> Multi.insert(:work_order, fn %{reason: reason} ->
      build(job.workflow, reason)
    end)
    |> Multi.insert(:attempt, fn %{work_order: work_order, reason: reason} ->
      AttemptService.build_attempt(work_order, reason)
    end)
    |> Multi.insert(:attempt_run, fn %{
                                       attempt: attempt,
                                       dataclip: dataclip
                                     } ->
      AttemptRun.new()
      |> Ecto.Changeset.put_assoc(:attempt, attempt)
      |> Ecto.Changeset.put_assoc(
        :run,
        Run.new(%{
          job_id: job.id,
          input_dataclip_id: dataclip.id
        })
      )
    end)
  end

  @doc """
  Creates a work_order.

  ## Examples

      iex> create_work_order(%{field: value})
      {:ok, %WorkOrder{}}

      iex> create_work_order(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_work_order(attrs \\ %{}) do
    %WorkOrder{}
    |> WorkOrder.changeset(attrs)
    |> Repo.insert()
  end

  def build(workflow, reason) do
    WorkOrder.new()
    |> Ecto.Changeset.put_assoc(:workflow, workflow)
    |> Ecto.Changeset.put_assoc(:reason, reason)
  end
end
