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

  def installation_repos(installation_id) do
    with {:ok, client} <- build_client(installation_id),
         {:ok, %Tesla.Env{status: 200, body: body}} <-
           get(client, "/installation/repositories") do
      {:ok, Enum.map(body["repositories"], fn g_repo -> g_repo["full_name"] end)}
    end
  end

  def get_repo_branches(installation_id, repo_name) do
    with {:ok, client} <- build_client(installation_id),
         {:ok, %Tesla.Env{status: 200, body: body}} <-
           get(client, "/repos/#{repo_name}/branches") do
      {:ok, Enum.map(body, fn b -> b["name"] end)}
    end
  end

  def fire_repository_dispatch(installation_id, repo_name, user_email) do
    with {:ok, client} <- build_client(installation_id),
         {:ok, %Tesla.Env{status: 204}} <-
           post(client, "/repos/#{repo_name}/dispatches", %{
             event_type: "sync_project",
             client_payload: %{
               message: "#{user_email} initiated a sync from Lightning"
             }
           }) do
      {:ok, :fired}
    end
  end

  defp build_client(installation_id) do
    %{cert: cert, app_id: app_id} =
      Application.get_env(:lightning, :github_app)
      |> Map.new()

    with {:ok, auth_token, _} <- GithubToken.build(cert, app_id) do
      client =
        Tesla.client([
          {Tesla.Middleware.Headers,
           [
             {"Authorization", "Bearer #{auth_token}"}
           ]},
          Tesla.Middleware.OpenTelemetry
        ])

      case post(
             client,
             "/app/installations/#{installation_id}/access_tokens",
             ""
           ) do
        {:ok, %{status: 201} = installation_token_resp} ->
          installation_token = installation_token_resp.body["token"]

          {:ok,
           Tesla.client([
             {Tesla.Middleware.Headers,
              [
                {"Authorization", "Bearer " <> installation_token}
              ]},
             Tesla.Middleware.OpenTelemetry
           ])}

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
