defmodule Lightning.UsageTracking.ResubmissionWorker do
  @moduledoc """
  Worker to find resubmit report that has not been failed submission.

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  @impl Oban.Worker
  def perform(%{args: %{"id" => _id}}) do
    {:error, "foo"}
  end
end
