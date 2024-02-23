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

  def wellknown_url(_sandbox) do
    config = Common.get_config(:google)
    config[:wellknown_url]
  end

  @impl true
  def build_client(wellknown_url, opts \\ []) do
    Common.build_client(:google, wellknown_url, opts)
  end

  @impl true
  def authorize_url(client, state, scopes \\ [], opts \\ []) do
    scopes = Enum.map(scopes, &urlify_scope/1)

    Common.authorize_url(client, state, scopes, opts)
  end

  defp urlify_scope(scope), do: "https://www.googleapis.com/auth/#{scope}"

  @impl true
  def get_token(client, _wellknown_url, params) do
    Common.get_token(client, params)
  end

  @impl true
  def refresh_token(client, token, _wellknown_url) do
    Common.refresh_token(client, token)
  end

  @impl true
  def refresh_token(token, wellknown_url) do
    {:ok, %OAuth2.Client{} = client} = build_client(wellknown_url)
    refresh_token(client, token, wellknown_url)
  end

  @impl true
  def get_userinfo(client, token, wellknown_url) do
    Common.get_userinfo(client, token, wellknown_url)
  end
end
