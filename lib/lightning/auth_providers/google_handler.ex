defmodule Lightning.AuthProviders.GoogleHandler do
  @moduledoc """
  Builds a Handler for Google OAuth2 SSO login from environment configuration.

  Set SSO_GOOGLE_CLIENT_ID and SSO_GOOGLE_CLIENT_SECRET to enable Google login.
  """

  alias Lightning.AuthProviders.Handler
  alias Lightning.AuthProviders.WellKnown

  @name "google"
  @authorization_endpoint "https://accounts.google.com/o/oauth2/v2/auth"
  @token_endpoint "https://oauth2.googleapis.com/token"
  @userinfo_endpoint "https://openidconnect.googleapis.com/v1/userinfo"

  def handler_name, do: @name

  @spec build() :: {:ok, Handler.t()} | {:error, :not_configured}
  def build do
    client_id = Lightning.Config.google_oauth(:client_id)
    client_secret = Lightning.Config.google_oauth(:client_secret)
    redirect_uri = Lightning.Config.google_oauth(:redirect_uri)

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
        scope: "openid email profile"
      )
    else
      {:error, :not_configured}
    end
  end
end
