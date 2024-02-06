defmodule Lightning.AuthProviders.Salesforce do
  @moduledoc """
  Handles the specifics of the Salesforce OAuth authentication process.
  """

  alias Lightning.AuthProviders.Common
  require Logger

  @doc """
  Builds the OAuth client for Salesforce using the specified options.

  ## Parameters
  - `opts`: A list of options that can be passed to customize the OAuth client.

  ## Returns
  - An `{:ok, client}` tuple on success, or `{:error, :invalid_config}` if the configuration is not set correctly.
  """
  def build_client(opts \\ []) do
    Common.build_client(:salesforce, opts)
  end

  @doc """
  Generates the authorization URL for Salesforce OAuth with the given client, state, and additional scopes.

  ## Parameters
  - `client`: The OAuth client.
  - `state`: A unique string to maintain state between the request and callback.
  - `additional_scopes`: Additional scopes to request access to.

  ## Returns
  - A URL string used for initiating the OAuth authorization process.
  """
  def authorize_url(client, state, additional_scopes \\ []) do
    predefined_scopes = ~W[refresh_token offline_access]
    scopes = predefined_scopes ++ additional_scopes

    Common.authorize_url(client, state, scopes)
  end

  @doc """
  Requests an authentication token from Salesforce.

  ## Parameters
  - `client`: The OAuth client.
  - `params`: The parameters needed to request the token.

  ## Returns
  - An OAuth token on success.
  """
  def get_token(client, params) do
    Common.get_token(client, params)
  end

  defp introspect({:ok, %OAuth2.AccessToken{access_token: access_token} = token}) do
    config = Common.get_config(:salesforce)

    Tesla.post(
      config[:introspect_url],
      "token=#{access_token}&client_id=#{config[:client_id]}&client_secret=#{config[:client_secret]}&token_type_hint=access_token",
      headers: [
        {"Accept", "application/json"},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]
    )
    |> handle_introspection_result(token)
  end

  defp introspect(result), do: result

  defp handle_introspection_result({:ok, %{status: status, body: body}}, token)
       when status in 200..202 do
    expires_at = Jason.decode!(body) |> Map.get("exp")
    updated_token = Map.update!(token, :expires_at, fn _ -> expires_at end)
    {:ok, updated_token}
  end

  defp handle_introspection_result({:ok, %{status: status}}, _token)
       when status not in 200..202,
       do: {:error, nil}

  @doc """
  Refreshes the Salesforce authentication token.

  ## Parameters
  - `client`: The OAuth client.
  - `token`: The current OAuth token.

  ## Returns
  - A refreshed OAuth token on success.
  """
  def refresh_token(client, token),
    do:
      Common.refresh_token(client, token)
      |> introspect()

  @doc """
  Retrieves user information from Salesforce using the provided OAuth token.

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
        :salesforce
      )
end
