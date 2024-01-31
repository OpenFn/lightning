defmodule Lightning.AuthProviders.Google do
  @moduledoc """
  Handles the specifics of the Google OAuth authentication process.
  """

  alias Lightning.AuthProviders.Common
  require Logger

  @doc """
  Builds the OAuth client for Google using the specified options.

  ## Parameters
  - `opts`: A list of options that can be passed to customize the OAuth client.

  ## Returns
  - An `{:ok, client}` tuple on success, or `{:error, :invalid_config}` if the configuration is not set correctly.
  """
  def build_client(opts \\ []) do
    Common.build_client(:google, opts)
  end

  @doc """
  Generates the authorization URL for Google OAuth with the given client and state.

  ## Parameters
  - `client`: The OAuth client.
  - `state`: A unique string to maintain state between the request and callback.

  ## Returns
  - A URL string used for initiating the OAuth authorization process.
  """
  def authorize_url(client, state, _additional_scopes \\ nil) do
    scopes = [
      "https://www.googleapis.com/auth/spreadsheets",
      "https://www.googleapis.com/auth/userinfo.profile"
    ]

    Common.authorize_url(client, state, scopes)
  end

  @doc """
  Requests an authentication token from Google.

  ## Parameters
  - `client`: The OAuth client.
  - `params`: The parameters needed to request the token.

  ## Returns
  - An OAuth token on success.
  """
  def get_token(client, params), do: Common.get_token(client, params)

  @doc """
  Refreshes the Google authentication token.

  ## Parameters
  - `client`: The OAuth client.
  - `token`: The current OAuth token.

  ## Returns
  - A refreshed OAuth token on success.
  """
  def refresh_token(client, token), do: Common.refresh_token(client, token)

  @doc """
  Retrieves user information from Google using the provided OAuth token.

  ## Parameters
  - `client`: The OAuth client.
  - `token`: The OAuth token.

  ## Returns
  - User information on success.
  """
  def get_userinfo(client, token),
    do:
      Common.get_userinfo(
        client,
        token,
        :google
      )
end
