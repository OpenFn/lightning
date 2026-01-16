defmodule Lightning.AuthProviders.OauthHTTPClient do
  @moduledoc """
  Handles OAuth interactions for generic providers, including token fetching,
  refreshing, and user information retrieval. This module uses Tesla to make HTTP
  requests configured with middleware appropriate for OAuth specific tasks.

  Returns structured error responses that integrate well with the audit system.
  """
  alias LightningWeb.RouteHelpers

  require Logger

  defp adapter do
    Application.get_env(:tesla, __MODULE__, [])[:adapter]
  end

  @doc """
  Revokes an OAuth token.

  Attempts to revoke both access_token and refresh_token for comprehensive cleanup.
  Per RFC 7009, providers should invalidate related tokens when one is revoked.

  ## Parameters
  - `client`: The client configuration containing client_id, client_secret, and revocation_endpoint.
  - `token`: The token data containing access_token and refresh_token.

  ## Returns
  - `:ok` on success (any token successfully revoked)
  - `{:error, %{status: integer(), error: term(), details: map()}}` on failure
  """
  def revoke_token(client, token) do
    tokens_to_revoke = [
      {"refresh_token", token["refresh_token"]},
      {"access_token", token["access_token"]}
    ]

    results =
      tokens_to_revoke
      |> Enum.filter(fn {_type, token_value} -> not is_nil(token_value) end)
      |> Enum.map(fn {token_type, token_value} ->
        revoke_single_token(client, token_value, token_type)
      end)

    case results do
      [] ->
        {:error,
         %{
           status: 400,
           error: "no_tokens_to_revoke",
           details: %{message: "No valid tokens found for revocation"}
         }}

      _ ->
        if Enum.any?(results, &match?(:ok, &1)) do
          :ok
        else
          List.last(results)
        end
    end
  end

  @doc """
  Fetches a new token using the authorization code provided by the OAuth provider.

  ## Parameters
  - `client`: The client configuration containing client_id, client_secret, and token_endpoint.
  - `code`: The authorization code received from the OAuth provider.

  ## Returns
  - `{:ok, token_data}` on success
  - `{:error, %{status: integer(), error: term(), details: map()}}` on failure
  """
  def fetch_token(client, code) do
    body = %{
      client_id: client.client_id,
      client_secret: client.client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: RouteHelpers.oidc_callback_url()
    }

    Tesla.client(
      [
        Tesla.Middleware.FormUrlencoded
      ],
      adapter()
    )
    |> Tesla.post(client.token_endpoint, body)
    |> handle_response([200])
    |> maybe_introspect(client)
  end

  @doc """
  Refreshes an existing token using the refresh token.

  ## Parameters
  - `client`: The client configuration containing client_id, client_secret, and token_endpoint.
  - `token`: The token configuration containing refresh_token

  ## Returns
  - `{:ok, refreshed_token_data}` on success with preserved refresh_token
  - `{:error, %{status: integer(), error: term(), details: map()}}` on failure
  """
  def refresh_token(client, token) do
    refresh_token_value = token["refresh_token"]

    if is_nil(refresh_token_value) or refresh_token_value == "" do
      {:error,
       %{
         status: 400,
         error: "invalid_request",
         details: %{message: "refresh_token is required"}
       }}
    else
      body = %{
        client_id: client.client_id,
        client_secret: client.client_secret,
        refresh_token: refresh_token_value,
        grant_type: "refresh_token"
      }

      Tesla.client(
        [
          Tesla.Middleware.FormUrlencoded
        ],
        adapter()
      )
      |> Tesla.post(client.token_endpoint, body)
      |> handle_response([200])
      |> maybe_introspect(client)
      |> case do
        {:ok, new_token} ->
          merged_token = merge_token_response(token, new_token)
          {:ok, merged_token}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Fetches user information from the OAuth provider using a valid access token.

  ## Parameters
  - `client`: The client configuration containing userinfo_endpoint.
  - `token`: The token configuration containing access_token.

  ## Returns
  - `{:ok, user_info}` on success
  - `{:error, %{status: integer(), error: term(), details: map()}}` on failure
  """
  def fetch_userinfo(client, token) do
    access_token = token["access_token"]

    if is_nil(access_token) or access_token == "" do
      {:error,
       %{
         status: 400,
         error: "invalid_request",
         details: %{message: "access_token is required"}
       }}
    else
      headers = [{"Authorization", "Bearer #{access_token}"}]

      Tesla.client([{Tesla.Middleware.Headers, headers}], adapter())
      |> Tesla.get(client.userinfo_endpoint)
      |> handle_response([200])
    end
  end

  @doc """
  Generates an authorization URL with specified parameters.

  ## Parameters
  - `client`: The client configuration containing client_id, and authorization_endpoint.
  - `params`: Additional parameters to include in the authorization URL.

  ## Returns
  - The fully formed authorization URL as a string.
  """
  def generate_authorize_url(client, params) do
    default_params = [
      access_type: "offline",
      prompt: "consent",
      client_id: client.client_id,
      redirect_uri: RouteHelpers.oidc_callback_url(),
      response_type: "code",
      scope: "",
      state: ""
    ]

    merged_params = Keyword.merge(default_params, params)
    encoded = URI.encode_query(merged_params)
    "#{client.authorization_endpoint}?#{encoded}"
  end

  defp revoke_single_token(client, token_value, token_type) do
    body = %{
      token: token_value,
      token_type_hint: token_type,
      client_id: client.client_id,
      client_secret: client.client_secret
    }

    Tesla.client(
      [
        Tesla.Middleware.FormUrlencoded
      ],
      adapter()
    )
    |> Tesla.post(client.revocation_endpoint, body)
    |> handle_response([200, 204])
    |> case do
      {:ok, _} ->
        Logger.debug("Successfully revoked #{token_type}")
        :ok

      {:error, error} ->
        Logger.warning("Failed to revoke #{token_type}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp maybe_introspect({:error, reason}, _client) do
    {:error, reason}
  end

  defp maybe_introspect({:ok, token}, client) do
    if Map.get(client, :introspection_endpoint) do
      case introspect(client, token) do
        {:ok, response} ->
          {:ok, Map.put(token, "expires_at", response["exp"])}

        {:error, _reason} ->
          Logger.warning(
            "Token introspection failed, proceeding without expires_at"
          )

          {:ok, token}
      end
    else
      {:ok, token}
    end
  end

  defp introspect(client, token) do
    body = %{
      token: token["access_token"],
      client_id: client.client_id,
      client_secret: client.client_secret,
      token_type_hint: "access_token"
    }

    Tesla.client(
      [
        Tesla.Middleware.FormUrlencoded
      ],
      adapter()
    )
    |> Tesla.post(client.introspection_endpoint, body)
    |> handle_response([200])
  end

  defp merge_token_response(original_token, new_token) do
    refresh_token =
      new_token["refresh_token"] || original_token["refresh_token"]

    new_token
    |> Map.put("refresh_token", refresh_token)
    |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_unix())
  end

  defp handle_response(
         {:ok, %Tesla.Env{status: status, body: body}},
         expected_statuses
       ) do
    if status in expected_statuses do
      case parse_response_body(body) do
        {:ok, parsed_body} ->
          {:ok, parsed_body}

        {:error, parse_error} ->
          {:error,
           %{
             status: status,
             error: "invalid_response_format",
             details: %{parse_error: inspect(parse_error), raw_body: body}
           }}
      end
    else
      error_details = parse_error_response(body, status)

      {:error,
       %{
         status: status,
         error: error_details.error,
         details: error_details.details
       }}
    end
  end

  defp handle_response(
         {:error, %Tesla.Error{reason: reason}},
         _expected_statuses
       ) do
    {:error,
     %{
       status: 0,
       error: "network_error",
       details: %{reason: inspect(reason)}
     }}
  end

  defp handle_response({:error, reason}, _expected_statuses) do
    {:error,
     %{
       status: 0,
       error: "unknown_error",
       details: %{reason: inspect(reason)}
     }}
  end

  defp parse_response_body(""), do: {:ok, %{}}
  defp parse_response_body(nil), do: {:ok, %{}}

  defp parse_response_body(body) when is_binary(body) do
    Jason.decode(body)
  end

  defp parse_response_body(body), do: {:ok, body}

  defp parse_error_response(body, status) do
    case parse_response_body(body) do
      {:ok, %{"error" => error, "error_description" => description}} ->
        %{
          error: error,
          details: %{
            description: description,
            status: status
          }
        }

      {:ok, %{"error" => error}} ->
        %{
          error: error,
          details: %{status: status}
        }

      {:ok, parsed_body} when is_map(parsed_body) ->
        %{
          error: "oauth_error",
          details: Map.put(parsed_body, :status, status)
        }

      _ ->
        %{
          error: "http_error",
          details: %{
            status: status,
            raw_response: inspect(body)
          }
        }
    end
  end
end
