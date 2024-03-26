defmodule Lightning.VersionControl.GithubClient do
  @moduledoc """
  Tesla github http client we use this to make any network requests
  to github from Lightning
  """
  use Tesla

  alias Lightning.VersionControl.GithubError
  alias Lightning.VersionControl.GithubToken

  require Logger

  plug(Tesla.Middleware.BaseUrl, "https://api.github.com")
  plug(Tesla.Middleware.JSON)

  def create_repo_dispatch_event(client, repo_name, body) do
    post(client, "/repos/#{repo_name}/dispatches", body)
  end

  def get_installations(client) do
    get(client, "/user/installations")
  end

  def get_installation_repos(client) do
    get(client, "/installation/repositories")
  end

  def get_repo_branches(client, repo_name) do
    get(client, "/repos/#{repo_name}/branches")
  end

  def get_repo_content(client, repo, path, ref) do
    get(client, "/repos/#{repo}/contents/#{path}", query: [ref: ref])
  end

  def delete_repo_content(client, repo, path, body) do
    delete(client, "/repos/#{repo}/contents/#{path}", body: body)
  end

  def create_blob(client, repo, body) do
    post(client, "/repos/#{repo}/git/blobs", body)
  end

  def create_tree(client, repo, body) do
    post(client, "/repos/#{repo}/git/trees", body)
  end

  def get_commit(client, repo, ref) do
    get(client, "/repos/#{repo}/commits/#{ref}")
  end

  def create_commit(client, repo, body) do
    post(client, "/repos/#{repo}/git/commits", body)
  end

  def create_ref(client, repo, body) do
    post(client, "/repos/#{repo}/git/refs", body)
  end

  def update_ref(client, repo, ref, body) do
    post(client, "/repos/#{repo}/git/refs/#{ref}", body)
  end

  def delete_ref(client, repo, ref) do
    delete(client, "/repos/#{repo}/git/refs/#{ref}")
  end

  def delete_app_grant(client, app_client_id, token) do
    delete(client, "/applications/#{app_client_id}/grant",
      body: %{access_token: token}
    )
  end

  def get_repo_public_key(client, repo) do
    get(client, "/repos/#{repo}/actions/secrets/public-key")
  end

  def get_repo_secret(client, repo, secret_name) do
    get(client, "/repos/#{repo}/actions/secrets/#{secret_name}")
  end

  def create_repo_secret(client, repo, secret_name, body) do
    put(client, "/repos/#{repo}/actions/secrets/#{secret_name}", body)
  end

  def build_oauth_client do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://github.com/login/oauth"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"accept", "application/vnd.github+json"}
       ]}
    ]

    {:ok, Tesla.client(middleware)}
  end

  def build_bearer_client(token) do
    middleware = [
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{token}"}
       ]},
      Tesla.Middleware.OpenTelemetry
    ]

    {:ok, Tesla.client(middleware)}
  end

  def build_basic_auth_client(username, password) do
    middleware = [
      {Tesla.Middleware.BasicAuth, [username: username, password: password]},
      Tesla.Middleware.OpenTelemetry
    ]

    {:ok, Tesla.client(middleware)}
  end

  def build_installation_client(installation_id) do
    %{cert: cert, app_id: app_id} =
      Application.fetch_env!(:lightning, :github_app)
      |> Map.new()

    with {:ok, auth_token, _} <- GithubToken.build(cert, app_id),
         {:ok, client} <- build_bearer_client(auth_token) do
      case post(
             client,
             "/app/installations/#{installation_id}/access_tokens",
             ""
           ) do
        {:ok, %{status: 201} = installation_token_resp} ->
          installation_token = installation_token_resp.body["token"]

          build_bearer_client(installation_token)

        {:ok, %{status: 404, body: body}} ->
          Logger.error("Unexpected GitHub Response: #{inspect(body)}")

          error =
            GithubError.installation_not_found(
              "GitHub Installation APP ID is misconfigured",
              body
            )

          Sentry.capture_exception(error)

          {:error, error}

        {:ok, %{status: 401, body: body}} ->
          Logger.error("Unexpected GitHub Response: #{inspect(body)}")

          error =
            GithubError.invalid_certificate(
              "GitHub Certificate is misconfigured",
              body
            )

          Sentry.capture_exception(error)

          {:error, error}
      end
    end
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
