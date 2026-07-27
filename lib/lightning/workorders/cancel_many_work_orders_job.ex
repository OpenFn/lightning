defmodule Lightning.WorkOrders.CancelManyWorkOrdersJob do
  @moduledoc """
  Cancels available runs for multiple work orders in chunked batches.

  Receives work order IDs and atomically cancels their `:available` runs
  in chunks of 100 until none remain. Each chunk is a single
  `UPDATE ... WHERE` -- no window for races with worker claims.
  """
  use Oban.Worker,
    queue: :scheduler,
    max_attempts: 5

  alias Lightning.Runs

  require Logger

  @chunk_size 100

  @impl Oban.Worker
  def perform(%{
        args: %{
          "work_order_ids" => work_order_ids,
          "project_id" => project_id
        }
      }) do
    cancel_in_chunks(work_order_ids, project_id)
    :ok
  end

  defp cancel_in_chunks(work_order_ids, project_id) do
    case Runs.cancel_available_for_work_orders(
           work_order_ids,
           project_id,
           @chunk_size
         ) do
      {:ok, %{runs: {n, _}}} when n > 0 ->
        cancel_in_chunks(work_order_ids, project_id)

      _ ->
        :ok
    end
  end
end
