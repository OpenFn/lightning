defmodule Lightning.VersionControl.GithubClient do
  @moduledoc """
  Tesla github http client we use this to make any network requests
  to github from Lightning
  """
  use Tesla
  require Logger
  alias Lightning.VersionControl.GithubToken

  plug(Tesla.Middleware.BaseUrl, "https://api.github.com")
  plug(Tesla.Middleware.JSON)

  def installation_repos(installation_id) do
    with {:ok, installation_client} <- build_client(installation_id),
         {:ok, %{status: 200} = repos_resp} <-
           installation_client
           |> get("/installation/repositories") do
      {:ok,
       repos_resp.body["repositories"]
       |> Enum.map(fn g_repo -> g_repo["full_name"] end)}
    else
      {:error, :installation_not_found, meta} ->
        installation_id_error(meta)

      {:error, :invalid_pem} ->
        invalid_pem_error()
    end
  end

  def get_repo_branches(installation_id, repo_name) do
    with {:ok, installation_client} <- build_client(installation_id),
         {:ok, %{status: 200} = branches} <-
           installation_client
           |> get("/repos/#{repo_name}/branches") do
      branch_names =
        branches.body
        |> Enum.map(fn b -> b["name"] end)

      {:ok, branch_names}
    else
      {:error, :installation_not_found, meta} ->
        installation_id_error(meta)

      {:error, :invalid_pem} ->
        invalid_pem_error()
    end
  end

  def fire_repository_dispatch(installation_id, repo_name, user_email) do
    with {:ok, installation_client} <- build_client(installation_id),
         {:ok, %{status: 204}} <-
           installation_client
           |> post("/repos/#{repo_name}/dispatches", %{
             event_type: "sync_project",
             client_payload: %{
               message: "#{user_email} initiated a sync from Lightning"
             }
           }) do
      {:ok, :fired}
    else
      {:error, :installation_not_found, meta} ->
        installation_id_error(meta)

      {:error, :invalid_pem} ->
        invalid_pem_error()

      err ->
        Logger.error(inspect(err))
        {:error, "Error Initiating sync"}
    end
  end

  def send_sentry_error(msg, meta \\ %{}) do
    Sentry.capture_message("Github configuration error",
      level: "warning",
      extra: meta,
      message: msg,
      tags: %{type: "github"}
    )
  end

  defp installation_id_error(meta) do
    send_sentry_error("Github Installation APP ID is misconfigured", meta)

    {:error,
     %{
       message:
         "Sorry, it seems that the GitHub App ID has not been properly configured for this instance of Lightning. Please contact the instance administrator"
     }}
  end

  defp invalid_pem_error do
    send_sentry_error("Github Cert is misconfigured")

    {:error,
     %{
       message:
         "Sorry, it seems that the GitHub cert has not been properly configured for this instance of Lightning. Please contact the instance administrator"
     }}
  end

  defp build_client(installation_id) do
    %{cert: cert, app_id: app_id} =
      Application.get_env(:lightning, :github_app)
      |> Map.new()

    with {:ok, auth_token, _} <- GithubToken.build(cert, app_id),
         client <-
           Tesla.client([
             {Tesla.Middleware.Headers,
              [
                {"Authorization", "Bearer #{auth_token}"}
              ]}
           ]),
         {:ok, installation_token_resp} <-
           client
           |> post("/app/installations/#{installation_id}/access_tokens", ""),
         %{status: 201} <- installation_token_resp do
      installation_token = installation_token_resp.body["token"]

      {:ok,
       Tesla.client([
         {Tesla.Middleware.Headers,
          [
            {"Authorization", "Bearer " <> installation_token}
          ]}
       ])}
    else
      %{status: 404} = err ->
        {:error, :installation_not_found, err}

      _unused_status ->
        {:error, :invalid_pem}
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
