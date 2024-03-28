defmodule Lightning.UsageTracking.GithubClient do
  use Tesla, only: [:head], docs: false

  alias Lightning.UsageTracking.ResponseProcessor

  @host "https://github.com/"

  def open_fn_commit?(commit_sha) do
    @host
    |> build_client
    |> head("OpenFn/lightning/commit/#{commit_sha}")
    |> elem(1)
    |> ResponseProcessor.successful_200?()
  end

  def build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}])
  end
end
