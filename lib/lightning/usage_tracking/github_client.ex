defmodule Lightning.UsageTracking.GithubClient do
  @moduledoc """
  A GitHub client to make unauthenticated HTTP requests to GitHub.
  """
  alias Lightning.UsageTracking.ResponseProcessor

  @host "https://github.com/"

  defp adapter do
    Application.get_env(:tesla, __MODULE__, [])[:adapter]
  end

  def open_fn_commit?(nil = _commit_sha), do: false
  def open_fn_commit?("" = _commit_sha), do: false

  def open_fn_commit?(commit_sha) do
    response =
      @host
      |> build_client()
      |> Tesla.head("OpenFn/lightning/commit/#{commit_sha}")

    ResponseProcessor.successful_200?(response)
  end

  def build_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}], adapter())
  end
end
