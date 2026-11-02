defmodule LightningWeb.API.Me.GithubTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.GithubHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.Repo

  @github "https://api.github.com"

  # Installations are read at once, so GitHub is one stub that answers by
  # URL, and each installation's token names it.
  defp stub_github(opts) do
    installations = Keyword.get(opts, :installations, %{})
    branches = Keyword.get(opts, :branches, %{})
    installations_status = Keyword.get(opts, :installations_status, 200)

    Mox.stub(Lightning.Tesla.Mock, :call, fn
      %{method: :get, url: @github <> "/user/installations"}, _opts ->
        body = %{
          "installations" =>
            Enum.map(
              Map.keys(installations),
              &%{"id" => &1, "account" => %{"type" => "User", "login" => "x"}}
            )
        }

        {:ok, %Tesla.Env{status: installations_status, body: body}}

      %{method: :post, url: @github <> "/app/installations/" <> rest}, _opts ->
        [id | _access_tokens] = String.split(rest, "/")
        {:ok, %Tesla.Env{status: 201, body: %{"token" => "installation-" <> id}}}

      %{method: :get, url: @github <> "/installation/repositories"} = env,
      _opts ->
        {_, "Bearer installation-" <> id} =
          List.keyfind(env.headers, "Authorization", 0)

        case Map.fetch!(installations, String.to_integer(id)) do
          :fails ->
            {:ok, %Tesla.Env{status: 500, body: %{}}}

          repos ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "total_count" => length(repos),
                 "repositories" =>
                   for(
                     name <- repos,
                     do: %{"full_name" => name, "default_branch" => "main"}
                   )
               }
             }}
        end

      %{method: :get, url: @github <> "/repos/" <> rest}, _opts ->
        repo = String.replace_suffix(rest, "/branches", "")

        {:ok,
         %Tesla.Env{
           status: 200,
           body: for(name <- Map.fetch!(branches, repo), do: %{"name" => name})
         }}
    end)
  end

  defp connected_user, do: set_valid_github_oauth_token!(insert(:user))

  describe "disconnecting" do
    test "asks GitHub to revoke the grant, forgets the token and answers 204" do
      user = connected_user()

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{method: :delete, url: @github <> "/applications/abcd1234/grant"},
        _opts ->
          {:ok, %Tesla.Env{status: 204, body: ""}}
      end)

      conn =
        build_conn()
        |> session_conn(user)
        |> delete(~p"/api/me/github_connection")

      assert conn.status == 204
      assert conn.resp_body == ""
      assert is_nil(Repo.reload!(user).github_oauth_token)
    end

    @tag :capture_log
    test "forgets the token even when GitHub refuses to revoke it" do
      user = connected_user()

      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 500, body: %{}}}
      end)

      conn =
        build_conn()
        |> session_conn(user)
        |> delete(~p"/api/me/github_connection")

      assert conn.status == 204
      assert is_nil(Repo.reload!(user).github_oauth_token)
    end

    # Another request disconnecting first leaves what this one asked for.
    @tag :capture_log
    test "answers 204 when another request disconnects while GitHub is asked" do
      user = connected_user()

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{method: :delete, url: @github <> "/applications/abcd1234/grant"},
        _opts ->
          Repo.query!(
            "UPDATE users SET github_oauth_token = NULL WHERE id = $1",
            [Ecto.UUID.dump!(user.id)]
          )

          {:ok, %Tesla.Env{status: 404, body: %{}}}
      end)

      conn =
        build_conn()
        |> session_conn(user)
        |> delete(~p"/api/me/github_connection")

      assert conn.status == 204
      assert is_nil(Repo.reload!(user).github_oauth_token)
    end

    test "answers 204 when there was no connection, without asking GitHub" do
      Mox.expect(Lightning.Tesla.Mock, :call, 0, fn _env, _opts -> :unused end)

      conn =
        build_conn()
        |> session_conn(insert(:user))
        |> delete(~p"/api/me/github_connection")

      assert conn.status == 204
    end
  end

  describe "listing repositories" do
    test "lists every installation's repositories by name, paged" do
      stub_github(
        installations: %{
          1 => ["openfn/zeta", "openfn/Alpha"],
          2 => ["ada/beta"]
        }
      )

      conn =
        build_conn()
        |> session_conn(connected_user())
        |> get(~p"/api/me/github_repos?page_size=2")

      url = LightningWeb.Endpoint.url() <> "/api/me/github_repos"

      assert json_response(conn, 200) == %{
               "data" => [
                 %{
                   "full_name" => "ada/beta",
                   "default_branch" => "main",
                   "installation_id" => "2"
                 },
                 %{
                   "full_name" => "openfn/Alpha",
                   "default_branch" => "main",
                   "installation_id" => "1"
                 }
               ],
               "links" => %{
                 "self" => url <> "?page=1&page_size=2",
                 "first" => url <> "?page=1&page_size=2",
                 "last" => url <> "?page=2&page_size=2",
                 "next" => url <> "?page=2&page_size=2",
                 "prev" => nil
               }
             }
    end

    test "lists none for an installation whose repositories can't be read" do
      stub_github(installations: %{1 => :fails, 2 => ["ada/beta"]})

      conn =
        build_conn()
        |> session_conn(connected_user())
        |> get(~p"/api/me/github_repos")

      assert [%{"full_name" => "ada/beta"}] = json_response(conn, 200)["data"]
    end

    test "answers no connection, or one whose refresh token expired, with forbidden" do
      expired = set_expired_github_oauth_token!(insert(:user))

      for user <- [insert(:user), expired] do
        build_conn()
        |> session_conn(user)
        |> get(~p"/api/me/github_repos")
        |> assert_problem(403, :forbidden, [])
      end
    end

    @tag :capture_log
    test "answers service_unavailable when GitHub won't list the installations" do
      stub_github(installations: %{}, installations_status: 502)

      build_conn()
      |> session_conn(connected_user())
      |> get(~p"/api/me/github_repos")
      |> assert_problem(503, :service_unavailable, [])
    end
  end

  describe "listing a repository's branches" do
    test "lists the branches by name, finding the repository in the person's installations" do
      stub_github(
        installations: %{1 => ["ada/beta"], 2 => ["openfn/Alpha"]},
        branches: %{"openfn/Alpha" => ["main", "dev", "Feature"]}
      )

      conn =
        build_conn()
        |> session_conn(connected_user())
        |> get(~p"/api/me/github_repos/openfn/alpha/branches")

      assert json_response(conn, 200) == %{
               "data" => [
                 %{"name" => "dev"},
                 %{"name" => "Feature"},
                 %{"name" => "main"}
               ]
             }
    end

    test "answers a repository the person's installations can't reach with not_found" do
      stub_github(installations: %{1 => ["ada/beta"]})

      build_conn()
      |> session_conn(connected_user())
      |> get(~p"/api/me/github_repos/someone/private/branches")
      |> assert_problem(404, :not_found, [])
    end

    test "answers no connection with forbidden" do
      build_conn()
      |> session_conn(insert(:user))
      |> get(~p"/api/me/github_repos/ada/beta/branches")
      |> assert_problem(403, :forbidden, [])
    end
  end
end
