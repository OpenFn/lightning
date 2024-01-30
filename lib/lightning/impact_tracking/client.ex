defmodule Lightning.ImpactTracking.Client do
  @moduledoc """
  Client for Impact Tracker service


  """
  use Tesla, only: [:post], docs: false

  def submit_metrics(metrics, host) do
    build_client(host) |> post("/api/metrics", metrics)
  end

  defp build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}, Tesla.Middleware.JSON])
  end
end
