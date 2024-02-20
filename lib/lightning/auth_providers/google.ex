defmodule Lightning.AuthProviders.Google do
  @moduledoc """
  Handles the specifics of the Google OAuth authentication process.
  """
  @behaviour Lightning.AuthProviders.OAuthBehaviour

  alias Lightning.AuthProviders.Common
  require Logger

  @impl true
  def build_client(opts \\ []) do
    Common.build_client(:google, opts)
  end

  @impl true
  def authorize_url(client, state, scopes \\ [], opts \\ []) do
    scopes =
      scopes
      |> Enum.map(fn scope -> "https://www.googleapis.com/auth/#{scope}" end)

    Common.authorize_url(client, state, scopes, opts)
  end

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
