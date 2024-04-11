defmodule Lightning.UsageTracking.GithubClientTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias Lightning.UsageTracking.GithubClient

  @commit_sha "abc123"
  @url "https://github.com/OpenFn/lightning/commit/#{@commit_sha}"

  test "returns true if commit sha exists on OpenFn Lightning repo" do
    url = @url

    mock(fn
      %{
        method: :head,
        url: ^url,
        query: [],
        headers: [],
        body: nil,
        status: nil
      } ->
        %Tesla.Env{status: 200}
    end)

    assert GithubClient.open_fn_commit?(@commit_sha) == true
  end

  test "returns false if commit sha doesn't exist on OpenFn Lightning repo" do
    url = @url

    mock(fn
      %{
        method: :head,
        url: ^url
      } ->
        %Tesla.Env{status: 404}
    end)

    assert GithubClient.open_fn_commit?(@commit_sha) == false
  end

  test "returns false if commit sha is nil" do
    assert GithubClient.open_fn_commit?(nil) == false
  end

  test "returns false if commit sha is an empty string" do
    assert GithubClient.open_fn_commit?("") == false
  end
end
