defmodule Lightning.WorkOrders.ExportWorker do
  alias Lightning.Invocation
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams

  def start_export(%Project{} = project, %SearchParams{} = params) do
    Invocation.search_workorders(project, params) |> IO.inspect()
    :ok
  end
end
