defmodule Lightning.WorkOrderService do
  @moduledoc """
  The WorkOrderService.
  """

  import Ecto.Query, warn: false

  alias Lightning.Repo
  alias Lightning.WorkOrder

  @pubsub Lightning.PubSub

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
    |> Repo.insert(returning: true)
  end

  def build(workflow, reason) do
    WorkOrder.new()
    |> Ecto.Changeset.put_assoc(:workflow, workflow)
    |> Ecto.Changeset.put_assoc(:reason, reason)
  end

  def subscribe(project_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(project_id))
  end

  defp topic(project_id), do: "project:#{project_id}"
end
