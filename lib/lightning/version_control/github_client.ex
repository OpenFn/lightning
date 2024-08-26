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
    client |> post("/repos/#{repo_name}/dispatches", body) |> handle_resp([204])
  end

  def create_workflow_dispatch_event(client, repo_name, workflow_id, body) do
    client
    |> post(
      "repos/#{repo_name}/actions/workflows/#{workflow_id}/dispatches",
      body
    )
    |> handle_resp([204])
  end

  def get_installations(client) do
    client |> get("/user/installations") |> handle_resp([200])
  end

  def get_installation_repos(client) do
    client |> get("/installation/repositories") |> handle_resp([200])
  end

  def get_repo(client, repo_name) do
    client |> get("/repos/#{repo_name}") |> handle_resp([200])
  end

  def get_repo_branches(client, repo_name) do
    client |> get("/repos/#{repo_name}/branches") |> handle_resp([200])
  end

  def get_repo_content(client, repo, path, ref) do
    client
    |> get("/repos/#{repo}/contents/#{path}", query: [ref: ref])
    |> handle_resp([200])
  end

  def delete_repo_content(client, repo, path, body) do
    client
    |> delete("/repos/#{repo}/contents/#{path}", body: body)
    |> handle_resp([200])
  end

  def create_blob(client, repo, body) do
    client |> post("/repos/#{repo}/git/blobs", body) |> handle_resp([201])
  end

  def create_tree(client, repo, body) do
    client |> post("/repos/#{repo}/git/trees", body) |> handle_resp([201])
  end

  def get_commit(client, repo, ref) do
    client |> get("/repos/#{repo}/commits/#{ref}") |> handle_resp([200])
  end

  def create_commit(client, repo, body) do
    client |> post("/repos/#{repo}/git/commits", body) |> handle_resp([201])
  end

  def create_ref(client, repo, body) do
    client |> post("/repos/#{repo}/git/refs", body) |> handle_resp([201])
  end

  def update_ref(client, repo, ref, body) do
    client |> post("/repos/#{repo}/git/refs/#{ref}", body) |> handle_resp([200])
  end

  def delete_ref(client, repo, ref) do
    client |> delete("/repos/#{repo}/git/refs/#{ref}") |> handle_resp([204])
  end

  def delete_app_grant(client, app_client_id, token) do
    client
    |> delete("/applications/#{app_client_id}/grant",
      body: %{access_token: token}
    )
    |> handle_resp([204])
  end

  def get_repo_public_key(client, repo) do
    client
    |> get("/repos/#{repo}/actions/secrets/public-key")
    |> handle_resp([200])
  end

  def get_repo_secret(client, repo, secret_name) do
    client
    |> get("/repos/#{repo}/actions/secrets/#{secret_name}")
    |> handle_resp([200])
  end

  def create_repo_secret(client, repo, secret_name, body) do
    client
    |> put("/repos/#{repo}/actions/secrets/#{secret_name}", body)
    |> handle_resp([201, 204])
  end

  def delete_repo_secret(client, repo, secret_name) do
    client
    |> delete("/repos/#{repo}/actions/secrets/#{secret_name}")
    |> handle_resp([204])
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

        {:ok, %{status: 403, body: %{"message" => message} = resp}} ->
          {:error, GithubError.api_error(message, resp)}
      end
    end
  end

  defp handle_resp(result, success_statuses) do
    with {:ok, %Tesla.Env{status: status} = resp} <- result do
      if status in success_statuses do
        {:ok, resp}
      else
        {:error, resp}
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
