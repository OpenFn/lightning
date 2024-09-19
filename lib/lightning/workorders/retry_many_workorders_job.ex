defmodule Lightning.WorkOrders.RetryManyWorkOrdersJob do
  @moduledoc """
  Enqueue multiple work orders for retry.
  """
  use Oban.Worker,
    queue: :scheduler,
    max_attempts: 5

  alias Lightning.WorkOrders

  require Logger

  @impl Oban.Worker
  def perform(%{
        args: %{"runs_ids" => runs_ids, "created_by" => creating_user_id}
      }) do
    with {:error, changeset} <-
           WorkOrders.enqueue_many_for_retry(runs_ids, creating_user_id) do
      Logger.error("Error retrying workorders: #{inspect(changeset)}")
    end

    :ok
  end
end
