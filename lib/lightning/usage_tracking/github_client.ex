defmodule Lightning.UsageTracking.GithubClient do
  @moduledoc """
  A GitHub client to make unauthenticated HTTP requests to GitHub.
  """
  use Tesla, only: [:head], docs: false

  alias Lightning.UsageTracking.ResponseProcessor

  @host "https://github.com/"

  def open_fn_commit?(nil = _commit_sha), do: false
  def open_fn_commit?("" = _commit_sha), do: false

  def open_fn_commit?(commit_sha) do
    response =
      @host
      |> build_client()
      |> head("OpenFn/lightning/commit/#{commit_sha}")

    ResponseProcessor.successful_200?(response)
  end

  def build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}])
  end
end
