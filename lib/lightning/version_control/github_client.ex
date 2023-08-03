defmodule Lightning.VersionControl.GithubClient do
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

  defp get_installation_client(installation_id) do
    # build token
    {:ok, token, _} = build_token()

    # build client with token 
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

  def build_token() do
    github_config = Application.get_env(:lightning, :github_app)

    pem = File.read!(github_config[:cert_path])

    app_id = github_config[:app_id] |> String.to_integer()

    signer = Joken.Signer.create("RS256", %{"pem" => pem})

    issued_at = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.to_unix()

    exp = DateTime.add(DateTime.utc_now(), 10, :minute) |> DateTime.to_unix()

    claims = %{"iss" => app_id, "exp" => exp, "iat" => issued_at}

    GithubToken.generate_and_sign(claims, signer)
  end
end
