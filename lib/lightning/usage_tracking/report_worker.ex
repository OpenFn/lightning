defmodule Lightning.UsageTracking.ReportWorker do
  @moduledoc """
  Worker to generate report for given day

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  require Logger
  @impl Oban.Worker
  def perform(%{args: %{"date" => date}}) do
    Logger.info("ReportWorker was asked to report on #{date}")

    :ok
  end
end
