defmodule Lightning.AuthProviders.GithubHandler do
  @moduledoc """
  Builds a Handler for GitHub OAuth2 SSO login from environment configuration.

  Set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET to enable GitHub login.
  """

  alias Lightning.AuthProviders.Handler
  alias Lightning.AuthProviders.WellKnown

  @name "github"
  @authorization_endpoint "https://github.com/login/oauth/authorize"
  @token_endpoint "https://github.com/login/oauth/access_token"
  @userinfo_endpoint "https://api.github.com/user"

  def handler_name, do: @name

  @spec build() :: {:ok, Handler.t()} | {:error, :not_configured}
  def build do
    client_id = Lightning.Config.github_oauth(:client_id)
    client_secret = Lightning.Config.github_oauth(:client_secret)
    redirect_uri = Lightning.Config.github_oauth(:redirect_uri)

    if client_id && client_secret && redirect_uri do
      wellknown = %WellKnown{
        authorization_endpoint: @authorization_endpoint,
        token_endpoint: @token_endpoint,
        userinfo_endpoint: @userinfo_endpoint
      }

      Handler.new(@name,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        wellknown: wellknown,
        scope: "read:user user:email"
      )
    else
      {:error, :not_configured}
    end
  end
end
