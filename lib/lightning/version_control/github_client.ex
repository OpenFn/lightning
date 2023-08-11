defmodule Lightning.VersionControl.GithubClient do
  @moduledoc """
  Tesla github http client we use this to make any network requests
  to github from Lightning
  """
  use Tesla
  alias Lightning.VersionControl.GithubToken

  plug(Tesla.Middleware.BaseUrl, "https://api.github.com")
  plug(Tesla.Middleware.JSON)

  def installation_repos(installation_id) do
    installation_client = get_installation_client(installation_id)

    {:ok, repos} =
      installation_client
      |> get("/installation/repositories")

    repo_names =
      repos.body["repositories"]
      |> Enum.map(fn g_repo -> g_repo["full_name"] end)

    {:ok, repo_names}
  end

  def get_repo_branches(installation_id, repo_name) do
    installation_client = get_installation_client(installation_id)

    {:ok, branches} =
      installation_client
      |> get("/repos/" <> repo_name <> "/branches")

    branch_names =
      branches.body
      |> Enum.map(fn b -> b["name"] end)

    {:ok, branch_names}
  end

  def fire_repository_dispatch(installation_id, repo_name, user_name) do
    installation_client = get_installation_client(installation_id)

    {:ok, %{status: 204}} =
      installation_client
      |> post("/repos/" <> repo_name <> "/dispatches", %{
        event_type: "Sync by: #{user_name}"
      })

    {:ok, :fired}
  end

  defp get_installation_client(installation_id) do
    %{cert: cert, app_id: app_id} =
      Application.get_env(:lightning, :github_app)
      |> Map.new()

    {:ok, token, _} = GithubToken.build(cert, app_id)

    client =
      Tesla.client([
        {Tesla.Middleware.Headers,
         [
           {"Authorization", "Bearer " <> token}
         ]}
      ])

    {:ok, token} =
      client
      |> post("/app/installations/" <> installation_id <> "/access_tokens", "")

    installation_token = token.body["token"]

    Tesla.client([
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer " <> installation_token}
       ]}
    ])
  end
end

defmodule Lightning.VersionControl.GithubToken do
  @moduledoc """
  A module that `uses` Joken to handle building and signing application
  tokens for communicating with github

  See: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app#about-json-web-tokens-jwts
  """
  use Joken.Config

  @impl true
  def token_config do
    default_claims(default_exp: 60 * 10)
    |> add_claim(
      "iat",
      fn -> Joken.current_time() - 60 end,
      &(Joken.current_time() > &1)
    )
  end

  @spec build(cert :: String.t(), app_id :: String.t()) ::
          {:ok, Joken.bearer_token(), Joken.claims()}
          | {:error, Joken.error_reason()}
  def build(cert, app_id) do
    signer = Joken.Signer.create("RS256", %{"pem" => cert})

    generate_and_sign(%{"iss" => app_id}, signer)
  end
end
