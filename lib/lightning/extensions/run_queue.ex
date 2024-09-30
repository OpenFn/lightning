defmodule Lightning.Extensions.RunQueue do
  @moduledoc """
  Extension to customize the scheduling of workloads on Lightning Runtime.
  """

  @callback enqueue(run :: Ecto.Multi.t()) ::
              {:ok, %{required(Ecto.Multi.name()) => any()}}
              | {:error, Ecto.Multi.name(), any(),
                 %{required(Ecto.Multi.name()) => any()}}

  @callback enqueue_many(runs :: Ecto.Multi.t()) ::
              {:ok, %{required(Ecto.Multi.name()) => any()}}
              | {:error, Ecto.Multi.name(), any(),
                 %{required(Ecto.Multi.name()) => any()}}

  @callback claim(demand :: non_neg_integer()) ::
              {:ok, [Lightning.Run.t()]}

  @callback dequeue(run :: Lightning.Run.t()) ::
              {:ok, Lightning.Run.t()}
end
