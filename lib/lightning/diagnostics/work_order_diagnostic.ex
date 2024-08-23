defmodule Lightning.Diagnostics.WorkOrderDiagnostic do
  def new(work_order) do
    work_order |> Map.take([:id, :inserted_at])
  end
end
