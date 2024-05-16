defmodule Lightning.AuthProviders.OauthHTTPClient do
  @moduledoc """
  Handles OAuth interactions for generic providers, including token fetching,
  refreshing, and user information retrieval. This module uses Tesla to make HTTP
  requests configured with middleware appropriate for OAuth specific tasks.
  """

  use Tesla

  alias LightningWeb.RouteHelpers

  @doc """
  Fetches a new token using the authorization code provided by the OAuth provider.

  ## Parameters
  - `client`: The client configuration containing client_id, client_secret, and token_endpoint.
  - `code`: The authorization code received from the OAuth provider.

  ## Returns
  - `{:ok, token_data}` on success
  - `{:error, reason}` on failure
  """
  def fetch_token(client, code) do
    body = %{
      client_id: client.client_id,
      client_secret: client.client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: RouteHelpers.oidc_callback_url()
    }

    Tesla.client([Tesla.Middleware.FormUrlencoded])
    |> post(client.token_endpoint, body)
    |> handle_resp([200])
    |> maybe_introspect(client)
  end

  defp maybe_introspect({:ok, token}, client) do
    introspect(client, token)
  end

  defp maybe_introspect({:error, reason}, _client) do
    {:error, reason}
  end

  defp introspect(client, token) do
    if client.introspection_endpoint do
      body = %{
        token: token["access_token"],
        client_id: client.client_id,
        client_secret: client.client_secret,
        token_type_hint: "access_token"
      }

      Tesla.client([Tesla.Middleware.FormUrlencoded])
      |> post(client.introspection_endpoint, body)
      |> handle_resp([200])
      |> process_resp(token)
    else
      {:ok, token}
    end
  end

  defp process_resp({:ok, response}, token) do
    {:ok, Map.put(token, "expires_at", response["exp"])}
  end

  defp process_resp({:error, _reason}, token) do
    {:ok, token}
  end

  @doc """
  Refreshes an existing token using the refresh token.

  ## Parameters
  - `client_id`: The OAuth client ID.
  - `client_secret`: The OAuth client secret.
  - `refresh_token`: The refresh token provided by the OAuth provider.
  - `token_endpoint`: The endpoint to send the refresh request to.

  ## Returns
  - `{:ok, refreshed_token_data}` on success
  - `{:error, reason}` on failure
  """
  def refresh_token(client_id, client_secret, refresh_token, token_endpoint) do
    body = %{
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    }

    Tesla.client([Tesla.Middleware.FormUrlencoded])
    |> post(token_endpoint, body)
    |> handle_resp([200])
  end

  @doc """
  Fetches user information from the OAuth provider using a valid access token.

  ## Parameters
  - `token`: The access token.
  - `userinfo_endpoint`: The endpoint to retrieve user information.

  ## Returns
  - `{:ok, user_info}` on success
  - `{:error, reason}` on failure
  """
  def fetch_userinfo(token, userinfo_endpoint) do
    headers = [{"Authorization", "Bearer #{token}"}]

    get(userinfo_endpoint, headers: headers)
    |> handle_resp([200])
  end

  @doc """
  Generates an authorization URL with specified parameters.

  ## Parameters
  - `base_url`: The base URL of the OAuth provider.
  - `client_id`: The client ID.
  - `params`: Additional parameters to include in the authorization URL.

  ## Returns
  - The fully formed authorization URL as a string.
  """
  def generate_authorize_url(base_url, client_id, params) do
    default_params = [
      access_type: "offline",
      client_id: client_id,
      prompt: "consent",
      redirect_uri: RouteHelpers.oidc_callback_url(),
      response_type: "code",
      scope: "",
      state: ""
    ]

    merged_params = Keyword.merge(default_params, params)
    encoded_params = URI.encode_query(merged_params)

    "#{base_url}?#{encoded_params}"
  end

  defp handle_resp(result, success_statuses) do
    case result do
      {:ok, %Tesla.Env{status: status, body: body}} ->
        if status in success_statuses do
          Jason.decode(body)
        else
          {:error, "#{inspect(body)}"}
        end

      {:error, reason} ->
        {:error, "#{inspect(reason)}"}
    end
  end

  @doc """
  Determines if the token data is still considered fresh.

  ## Parameters
  - `params`: a map containing token data with `expires_at` or `expires_in` keys.
  - `threshold`: the number of time units before expiration to consider the token still fresh.
  - `time_unit`: the unit of time to consider for the threshold comparison.

  ## Returns
  - `true` if the token is fresh.
  - `{:error, reason}` if the token's expiration data is missing or invalid.
  """
  @spec still_fresh(map(), integer(), atom()) :: boolean() | {:error, String.t()}
  def still_fresh(token_body, threshold \\ 5, time_unit \\ :minute)

  def still_fresh(%{"expires_at" => nil} = _token_body, _threshold, _time_unit),
    do: false

  def still_fresh(%{"expires_in" => nil} = _token_body, _threshold, _time_unit),
    do: false

  def still_fresh(params, threshold, time_unit) do
    current_time = DateTime.utc_now()

    expiration_time =
      case {Map.fetch(params, "expires_at"), Map.fetch(params, "expires_in")} do
        {{:ok, expires_at}, :error} -> expires_at
        {:error, {:ok, expires_in}} -> expires_in
        _ -> {:error, "No valid expiration data found"}
      end

    if is_integer(expiration_time) do
      expiration_time = DateTime.from_unix!(expiration_time)
      time_remaining = DateTime.diff(expiration_time, current_time, time_unit)
      time_remaining >= threshold
    else
      expiration_time
    end
  end
end
