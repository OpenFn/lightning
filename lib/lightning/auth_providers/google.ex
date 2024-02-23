defmodule Lightning.AuthProviders.Google do
  @moduledoc """
  Handles the specifics of the Google OAuth authentication process.
  """
  @behaviour Lightning.AuthProviders.OAuthBehaviour

  alias Lightning.AuthProviders.Common
  require Logger

  def provider_name, do: "Google"

  def scopes,
    do: %{
      optional: [],
      mandatory: ~W(userinfo.email userinfo.profile spreadsheets)
    }

  def scopes_doc_url,
    do: "https://developers.google.com/identity/protocols/oauth2/scopes"

  @impl true
  def build_client(opts \\ []) do
    Common.build_client(:google, opts)
  end

  @impl true
  def authorize_url(client, state, scopes \\ [], opts \\ []) do
    scopes = Enum.map(scopes, &urlify_scope/1)

    Common.authorize_url(client, state, scopes, opts)
  end

  defp urlify_scope(scope), do: "https://www.googleapis.com/auth/#{scope}"

  @impl true
  def get_token(client, params) do
    Common.get_token(client, params)
  end

  @impl true
  def refresh_token(client, token) do
    Common.refresh_token(client, token)
  end

  @impl true
  def refresh_token(token) do
    {:ok, %OAuth2.Client{} = client} = build_client()
    refresh_token(client, token)
  end

  @impl true
  def get_userinfo(client, token) do
    Common.get_userinfo(client, token, :google)
  end
end
