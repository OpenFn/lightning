defmodule Lightning.UsageTracking.GithubClient do
  @moduledoc """
  A github client to make unauthenticated HTTP requests to Github.
  """
  use Tesla, only: [:head], docs: false

  alias Lightning.UsageTracking.ResponseProcessor

  @host "https://github.com/"

  def open_fn_commit?(nil = _commit_sha), do: false
  def open_fn_commit?("" = _commit_sha), do: false

  def open_fn_commit?(commit_sha) do
    {_ok, env} =
      @host
      |> build_client()
      |> head("OpenFn/lightning/commit/#{commit_sha}")

    ResponseProcessor.successful_200?(env)
  end

  def build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}])
  end
end
