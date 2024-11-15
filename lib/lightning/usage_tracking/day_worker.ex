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
      Lightning.Config.usage_tracking_enabled?(),
      Lightning.current_time(),
      batch_size
    )

    :ok
  end
end
