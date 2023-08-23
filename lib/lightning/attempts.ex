defmodule Lightning.Attempts do
  alias Lightning.Repo

  @doc """
  Enqueue an attempt to be processed.
  """
  def enqueue(attempt) do
    Lightning.Attempts.Queue.new(attempt)
    |> Repo.insert()
  end

  # @doc """
  # Claim an available attempt.

  # Returns `nil` if no attempt is available.
  # """
  # def claim() do
  # end

  # @doc """
  # Removes an attempt from the queue.
  # """
  # def dequeue(attempt) do
  # end
end
