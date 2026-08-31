defmodule Lightning.Workflows.Stats do
  @moduledoc """
  Stats for a single workflow, shaped for the workflow health page.

  One public function per chart, each returning only what that chart draws. The
  page requests them separately so a cheap chart renders without waiting on an
  expensive one — a single merged payload would make every chart pay for the
  slowest query.

  Deliberately independent of `Lightning.DashboardStats`, which serves the
  workflow list view. The two answer similar questions today, but the list view
  batches across many workflows to avoid an N+1 while this page queries one, and
  their windows will diverge as soon as this page grows a range picker. Sharing
  the module would make each page pay for the other's requirements.
  """
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  @default_days_back 30

  @wo_active WorkOrder.active_states()

  @doc """
  Work order counts by outcome over the last `days_back` days.

  The window is echoed as bounds rather than a day count, so a range picker
  lands as a request param instead of a payload change.
  """
  def outcomes(%Workflow{id: workflow_id}, days_back \\ @default_days_back)
      when days_back > 0 do
    to = DateTime.utc_now()
    since = DateTime.add(to, -days_back, :day)

    %{
      window: %{from: since, to: to},
      counts: count_workorders(workflow_id, since)
    }
  end

  # `:success` is success, anything still running is pending, and everything
  # else — cancelled, killed, crashed, failed, exception, lost — is a failure.
  # Same bucketing the workflow list view shows, so the two pages agree.
  defp count_workorders(workflow_id, since) do
    from(wo in WorkOrder,
      where: wo.workflow_id == ^workflow_id and wo.inserted_at > ^since,
      group_by: wo.state,
      select: {wo.state, count(wo.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{success: 0, failed: 0, pending: 0}, fn
      {:success, count}, acc -> %{acc | success: count}
      {state, count}, acc when state in @wo_active -> add(acc, :pending, count)
      {_other, count}, acc -> add(acc, :failed, count)
    end)
  end

  defp add(acc, key, count), do: Map.update!(acc, key, &(&1 + count))
end
