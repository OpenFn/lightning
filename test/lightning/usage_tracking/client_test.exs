defmodule Lightning.UsageTracking.ClientTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias Lightning.UsageTracking.Client

  @host "https://foo.bar"
  @url "#{@host}/api/metrics"
  @metrics %{some: :metrics}

  describe ".submit_metrics" do
    setup do
      %{
        metrics: @metrics,
        serialised_metrics: @metrics |> Jason.encode!(),
        url: @url
      }
    end

    test "indicates successful submission of metrics",
         %{metrics: metrics, serialised_metrics: serialised_metrics, url: url} do
      mock(fn
        %{
          method: :post,
          url: ^url,
          body: ^serialised_metrics,
          headers: [{"content-type", "application/json"}]
        } ->
          %Tesla.Env{status: 200, body: %{status: "great"}}

        _ ->
          flunk("Unrecognised call")
      end)

      assert Client.submit_metrics(metrics, @host) == :ok
    end

    test "indicates unsuccessful submission of metrics",
         %{metrics: metrics, serialised_metrics: serialised_metrics, url: url} do
      mock(fn
        %{
          method: :post,
          url: ^url,
          body: ^serialised_metrics,
          headers: [{"content-type", "application/json"}]
        } ->
          %Tesla.Env{status: 500, body: %{}}

        _ ->
          flunk("Unrecognised call")
      end)

      assert Client.submit_metrics(metrics, @host) == :error
    end
  end

  describe ".reachable?/1" do
    setup do
      %{url: "#{@host}/"}
    end

    test "indicates if host is reachable", %{url: url} do
      mock(fn %{method: :head, url: ^url} -> %Tesla.Env{status: 200} end)

      assert Client.reachable?(@host) == true
    end

    test "indicates if the host is not reachable", %{url: url} do
      mock(fn %{method: :head, url: ^url} -> %Tesla.Env{status: 500} end)

      assert Client.reachable?(@host) == false
    end
  end
end
