defmodule Lightning.UsageTracking.Client do
  @moduledoc """
  Client for Usage Tracker service


  """
  use Tesla, only: [:post], docs: false

  alias Lightning.UsageTracking.ResponseProcessor

  def submit_metrics(metrics, host) do
    build_client(host)
    |> post("/api/metrics", metrics)
    |> elem(1)
    |> ResponseProcessor.successful?()
    |> then(fn
      true -> :ok
      false -> :error
    end)
  end

  defp build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}, Tesla.Middleware.JSON])
  end
end
