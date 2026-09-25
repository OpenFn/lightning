defmodule LightningWeb.TokenExchangeController do
  @moduledoc """
  The OAuth 2.0 authorization server a service account trades a signed
  assertion with for an access token: its RFC 8414 metadata document and its
  token endpoint.
  """
  use LightningWeb, :controller

  alias Lightning.ServiceAccount.AccessToken
  alias Lightning.ServiceAccount.Assertion

  require Logger

  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

  def metadata(conn, _params) do
    json(conn, %{
      issuer: AccessToken.issuer(),
      token_endpoint: url(~p"/api/oauth/token"),
      grant_types_supported: ["client_credentials"],
      token_endpoint_auth_methods_supported: ["private_key_jwt"],
      token_endpoint_auth_signing_alg_values_supported: ["RS256"],
      scopes_supported: AccessToken.scopes(),
      response_types_supported: []
    })
  end

  def token(conn, _params) do
    params = conn.body_params

    with :ok <- form_encoded(conn),
         :ok <- client_credentials(params),
         {:ok, assertion} <- client_assertion(params),
         {:ok, scopes} <- requested_scopes(params),
         {:ok, account} <- authenticate(assertion, params) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> json(%{
        access_token: AccessToken.issue(account, scopes),
        token_type: "Bearer",
        expires_in: AccessToken.lifetime(),
        scope: Enum.join(scopes, " ")
      })
    else
      {:error, :invalid_client} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_client"})

      {:error, error} ->
        conn |> put_status(:bad_request) |> json(%{error: error})
    end
  end

  defp form_encoded(conn) do
    case get_req_header(conn, "content-type") do
      ["application/x-www-form-urlencoded" <> _] -> :ok
      _other -> {:error, :invalid_request}
    end
  end

  defp client_credentials(%{"grant_type" => "client_credentials"}), do: :ok

  defp client_credentials(%{"grant_type" => grant_type})
       when is_binary(grant_type),
       do: {:error, :unsupported_grant_type}

  defp client_credentials(_params), do: {:error, :invalid_request}

  defp client_assertion(%{
         "client_assertion_type" => @assertion_type,
         "client_assertion" => assertion
       })
       when is_binary(assertion),
       do: {:ok, assertion}

  defp client_assertion(_params), do: {:error, :invalid_request}

  defp requested_scopes(%{"scope" => scope}) when is_binary(scope) do
    case String.split(scope) do
      [] ->
        {:ok, AccessToken.scopes()}

      scopes ->
        if Enum.all?(scopes, &(&1 in AccessToken.scopes())),
          do: {:ok, Enum.uniq(scopes)},
          else: {:error, :invalid_scope}
    end
  end

  defp requested_scopes(%{"scope" => _}), do: {:error, :invalid_request}
  defp requested_scopes(_params), do: {:ok, AccessToken.scopes()}

  defp authenticate(assertion, params) do
    case Assertion.verify(assertion, url(~p"/api/oauth/token")) do
      {:ok, account} ->
        if params["client_id"] in [nil, account.id],
          do: {:ok, account},
          else: refuse(:wrong_client_id)

      {:error, reason} ->
        refuse(reason)
    end
  end

  defp refuse(reason) do
    Logger.info("Refused a service account assertion: #{reason}")
    {:error, :invalid_client}
  end
end
