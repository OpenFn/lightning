defmodule Lightning.WorkOrders.Events do
  @moduledoc false

  defmodule WorkOrderCreated do
    @moduledoc false
    defstruct work_order: nil, project_id: nil
  end

  defmodule WorkOrderUpdated do
    @moduledoc false
    defstruct work_order: nil
  end

  defmodule RunCreated do
    @moduledoc false
    defstruct run: nil, project_id: nil, from_rejected_workorder: false
  end

  defmodule RunUpdated do
    @moduledoc false
    defstruct run: nil
  end

  def work_order_created(project_id, work_order) do
    Lightning.broadcast(
      topic(project_id),
      %WorkOrderCreated{work_order: work_order, project_id: project_id}
    )
  end

  def work_order_updated(project_id, work_order) do
    Lightning.broadcast(
      topic(project_id),
      %WorkOrderUpdated{work_order: work_order}
    )
  end

  def run_created(project_id, run) do
    event = %RunCreated{run: run, project_id: project_id}
    Lightning.broadcast(topic(project_id), event)
    Lightning.broadcast(topic(), event)
  end

  def run_updated(project_id, run) do
    Lightning.broadcast(
      topic(project_id),
      %RunUpdated{run: run}
    )
  end

  def subscribe do
    topic() |> Lightning.subscribe()
  end

  def subscribe(project_id) do
    Lightning.subscribe(topic(project_id))
  end

  defp topic, do: "all_events"
  defp topic(project_id), do: "project:#{project_id}"
end
