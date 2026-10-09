defmodule LightningWeb.TokenExchangeController do
  @moduledoc """
  The OAuth 2.0 authorization server a service account trades a signed
  assertion with for an access token: its RFC 8414 metadata document and its
  token endpoint.
  """
  use LightningWeb, :controller

  alias Lightning.Repo
  alias Lightning.ServiceAccount.AccessToken
  alias Lightning.ServiceAccount.Assertion
  alias Lightning.ServiceAccount.Audit

  require Logger

  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @refusal_log_window :timer.minutes(1)

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
      account |> Audit.token_issued(scopes) |> Repo.insert!()

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
    scopes = String.split(scope)

    if scopes != [] and Enum.all?(scopes, &(&1 in AccessToken.scopes())),
      do: {:ok, Enum.uniq(scopes)},
      else: {:error, :invalid_scope}
  end

  defp requested_scopes(%{"scope" => _}), do: {:error, :invalid_request}
  defp requested_scopes(_params), do: {:error, :invalid_scope}

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
    :telemetry.execute(
      [:lightning, :service_account, :assertion_refused],
      %{count: 1},
      %{reason: reason}
    )

    # One line per reason per minute per node, so a caller hammering the
    # endpoint can't flood the logs; telemetry still counts every refusal.
    case Hammer.check_rate(refusal_log_bucket(reason), @refusal_log_window, 1) do
      {:allow, _count} ->
        Logger.warning("Refused a service account assertion: #{reason}")

      {:deny, _limit} ->
        :ok
    end

    {:error, :invalid_client}
  end

  @doc false
  def refusal_log_bucket(reason), do: "service_account_refusal_log:#{reason}"
end
