defmodule Lightning.UsageTracking.Client do
  @moduledoc """
  Client for Usage Tracker service


  """
  use Tesla, only: [:head, :post], docs: false

  alias Lightning.UsageTracking.ResponseProcessor

  def submit_metrics(metrics, host) do
    response =
      host
      |> build_client()
      |> post("/api/metrics", metrics)

    if ResponseProcessor.successful?(response), do: :ok, else: :error
  end

  def reachable?(host) do
    build_head_client(host)
    |> head("/")
    |> ResponseProcessor.successful?()
  end

  defp build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}, Tesla.Middleware.JSON])
  end

  defp build_head_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}])
  end
end
