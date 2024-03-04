defmodule Lightning.UsageTracking.DayWorker do
  @moduledoc """
  Worker to manage per-day report generation

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.UsageTracking

  @impl Oban.Worker
  def perform(_opts) do
    env = Application.get_env(:lightning, :usage_tracking)

    if env[:enabled] do
      UsageTracking.enable_daily_report(DateTime.utc_now())
    else
      UsageTracking.disable_daily_report()
    end

    :ok
  end
end
