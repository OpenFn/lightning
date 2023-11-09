defmodule Lightning.WorkOrders.Events do
  @moduledoc false

  defmodule WorkOrderCreated do
    @moduledoc false
    defstruct work_order: nil
  end

  defmodule WorkOrderUpdated do
    @moduledoc false
    defstruct work_order: nil
  end

  defmodule AttemptCreated do
    @moduledoc false
    defstruct attempt: nil
  end

  defmodule AttemptUpdated do
    @moduledoc false
    defstruct attempt: nil
  end

  def work_order_created(project_id, work_order) do
    Lightning.broadcast(
      topic(project_id),
      %WorkOrderCreated{work_order: work_order}
    )
  end

  def work_order_updated(project_id, work_order) do
    Lightning.broadcast(
      topic(project_id),
      %WorkOrderUpdated{work_order: work_order}
    )
  end

  def attempt_created(project_id, attempt) do
    Lightning.broadcast(
      topic(project_id),
      %AttemptCreated{attempt: attempt}
    )
  end

  def attempt_updated(project_id, attempt) do
    Lightning.broadcast(
      topic(project_id),
      %AttemptUpdated{attempt: attempt}
    )
  end

  def subscribe(project_id) do
    Lightning.subscribe(topic(project_id))
  end

  defp topic(project_id), do: "project:#{project_id}"
end
