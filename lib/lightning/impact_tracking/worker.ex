defmodule Lightning.ImpactTracking.Worker do
  @moduledoc """
  Ensures repeated submissions of anonymised metrics to the Impact Tracker
  service


  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.ImpactTracking.Client

  @impl Oban.Worker
  def perform(_opts) do
    if Application.get_env(:lightning, :impact_tracking)[:enabled] do
      host = Application.get_env(:lightning, :impact_tracking)[:host]

      Client.submit_metrics(%{}, host)
    end

    :ok
  end
end
