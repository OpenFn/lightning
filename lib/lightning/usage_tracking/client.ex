defmodule Lightning.UsageTracking.Client do
  @moduledoc """
  Client for Usage Tracker service


  """
  use Tesla, only: [:post], docs: false

  alias Lightning.UsageTracking.ResponseProcessor

  def submit_metrics(metrics, host) do
    response =
      host
      |> build_client()
      |> post("/api/metrics", metrics)

    if ResponseProcessor.successful?(response), do: :ok, else: :error
  end

  defp build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}, Tesla.Middleware.JSON])
  end
end
