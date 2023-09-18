defmodule Lightning.Attempts do
  defmodule Adaptor do
    @moduledoc """
    Behaviour for implementing an adaptor for the Lightning.Attempts module.
    """

    @callback enqueue(
                attempt ::
                  Lightning.Attempt.t() | Ecto.Changeset.t(Lightning.Attempt.t())
              ) ::
                {:ok, Lightning.Attempt.t()}
                | {:error, Ecto.Changeset.t(Lightning.Attempt.t())}

    @callback claim(demand :: non_neg_integer()) ::
                {:ok, [Lightning.Attempt.t()]}

    @callback dequeue(attempt :: Lightning.Attempt.t()) ::
                {:ok, Lightning.Attempt.t()}

    @callback resolve(attempt :: Lightning.Attempt.t()) ::
                {:ok, Lightning.Attempt.t()}
  end

  @behaviour Adaptor

  @doc """
  Enqueue an attempt to be processed.
  """
  @impl true
  def enqueue(attempt) do
    adaptor().enqueue(attempt)
  end

  # @doc """
  # Claim an available attempt.
  #
  # The `demand` parameter is used to request more than a since attempt,
  # all implementation should default to 1.
  # """
  @impl true
  def claim(demand \\ 1) do
    adaptor().claim(demand)
  end

  # @doc """
  # Marks an attempt as resolved.
  # """
  @impl true
  def resolve(attempt) do
    adaptor().resolve(attempt)
  end

  # @doc """
  # Removes an attempt from the queue.
  # """
  @impl true
  def dequeue(attempt) do
    adaptor().dequeue(attempt)
  end

  defp adaptor do
    Lightning.Config.attempts_adaptor()
  end
end
