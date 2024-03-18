defmodule Lightning.UsageTracking.DayWorker do
  @moduledoc """
  Worker to manage per-day report generation

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.UsageTracking

  @impl Oban.Worker
  def perform(%{args: %{"batch_size" => batch_size}}) do
    UsageTracking.enqueue_reports(
      Application.get_env(:lightning, :usage_tracking)[:enabled],
      DateTime.utc_now(),
      batch_size
    )

    :ok
  end
end
