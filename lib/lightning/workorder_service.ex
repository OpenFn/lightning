defmodule Lightning.WorkOrderService do
  @moduledoc """
  The WorkOrders context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.WorkOrder

  @doc """
  Creates a workorder.

  ## Examples

      iex> create_workorder(%{field: value})
      {:ok, %WorkOrder{}}

      iex> create_workorder(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """

  def create_workorder(attrs \\ %{}) do
    %WorkOrder{}
    |> WorkOrder.changeset(attrs)
    |> Repo.insert()
  end
end
