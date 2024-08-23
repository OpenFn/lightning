defmodule Lightning.Diagnostics do

  alias Lightning.Diagnostics.WorkOrderDiagnostic
  alias Lightning.Repo
  alias Lightning.WorkOrder

  import Ecto.Query

  def workorders(workflow, inclusive_starts_at, exclusive_ends_at) do
    find_workorders =
      from w in WorkOrder,
        where: w.workflow_id == ^workflow.id,
        where: w.inserted_at >= ^inclusive_starts_at,
        where: w.inserted_at < ^exclusive_ends_at

    # Given the current use of the diagnostics, it is ok if this explodes.
    {:ok, diagnostics} = 
      Repo.transaction(fn ->
        find_workorders
        |> Repo.stream
        |> Enum.map(&WorkOrderDiagnostic.new/1)
      end)

    diagnostics
  end
end
