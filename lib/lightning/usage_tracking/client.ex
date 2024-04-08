defmodule Lightning.UsageTracking.Client do
  @moduledoc """
  Client for Usage Tracker service


  """
  use Tesla, only: [:head, :post], docs: false

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

  def reachable?(host) do
    build_head_client(host)
    |> head("/")
    |> elem(1)
    |> ResponseProcessor.successful?()
  end

  defp build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}, Tesla.Middleware.JSON])
  end

  defp build_head_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}])
  end
end
