defmodule Lightning.VersionControl.GithubClientTest do
  use ExUnit.Case, async: false
  alias Lightning.VersionControl
  import Lightning.Factories

  describe "Github Client" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Lightning.Repo)

      Tesla.Mock.mock(fn env ->
        case env.url do
          "https://api.github.com/app/installations/some-id/access_tokens" ->
            %Tesla.Env{status: 200, body: %{"token" => "some-token"}}

          "https://api.github.com/installation/repositories" ->
            %Tesla.Env{
              status: 200,
              body: %{"repositories" => [%{"full_name" => "org/repo"}]}
            }

          "https://api.github.com/repos/some/repo/branches" ->
            %Tesla.Env{status: 200, body: [%{"name" => "master"}]}

          "https://api.github.com/repos/some/repo/dispatches" ->
            %Tesla.Env{status: 204}
        end
      end)
    end

    test "client can fetch installation repos" do
      p_repo = insert(:project_repo)

      assert {:ok, ["org/repo"]} =
               VersionControl.fetch_installation_repos(p_repo.project_id)
    end

    test "client can fetch repo branches" do
      p_repo = insert(:project_repo)

      assert {:ok, ["master"]} =
               VersionControl.fetch_repo_branches(p_repo.project_id, p_repo.repo)
    end

    test "client can fire repository dispatch event" do
      p_repo = insert(:project_repo)

      assert {:ok, :fired} =
               VersionControl.run_sync(p_repo.project_id, "some-user-name")
    end
  end
end
