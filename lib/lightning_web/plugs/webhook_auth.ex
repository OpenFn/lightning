defmodule LightningWeb.Plugs.WebhookAuth do
  @moduledoc """
  A Plug to authenticate and authorize requests based on paths starting with '/i/'.
  It verifies the presence of correct API keys or Basic Authentication credentials.
  """
  use LightningWeb, :controller

  alias Lightning.Retry
  alias Lightning.Workflows
  alias Lightning.Workflows.WebhookAuthMethod

  require Logger

  @doc """
  Initializes the options.
  """
  def init(opts), do: opts

  @doc """
  Handles webhook auth for `/i/:webhook` requests.

  - **CORS preflight:** If the request method is `OPTIONS`, this plug is a no-op
    and returns the connection unchanged so upstream CORS handling can respond.
    This avoids doing DB lookups or emitting 401/404 on preflight requests.

  - **Auth flow:** For non-`OPTIONS` requests whose path matches `/i/:webhook`,
    this plug:
      1. Looks up the webhook trigger (with `workflow` and `edges`) and its
         `webhook_auth_methods`, wrapped in `Lightning.Retry.with_webhook_retry/2`
         so transient DB errors are retried.
      2. If the trigger is missing → responds **404** `{"error":"webhook_not_found"}`.
      3. If auth methods are configured:
         - If credentials match → assigns `:trigger` and continues.
         - If credentials are present but wrong → responds **404** (hide existence).
         - If credentials are missing → responds **401**.
      4. If retries exhaust due to DB issues → responds **503** with `Retry-After`
         based on `WEBHOOK_RETRY_TIMEOUT_MS`.

  Returns the (possibly halted) connection.
  """
  @spec call(Plug.Conn.t(), any) :: Plug.Conn.t()
  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts), do: conn

  def call(conn, _opts) do
    case conn.path_info do
      ["i" | [webhook | _rest]] ->
        Retry.with_webhook_retry(
          fn ->
            trigger =
              Workflows.get_webhook_trigger(webhook,
                include: [:workflow, :edges, :webhook_auth_methods]
              )

            methods = (trigger && trigger.webhook_auth_methods) || []

            {:ok, validate_auth(trigger, methods, conn)}
          end,
          retry_on: &Retry.retriable_error?/1,
          context: %{op: :webhook_auth_lookup, webhook: webhook}
        )
        |> case do
          {:ok, %Plug.Conn{} = conn} ->
            conn

          {:error, %DBConnection.ConnectionError{} = error} ->
            LightningWeb.Utils.respond_service_unavailable(
              conn,
              error,
              %{op: :webhook_auth_lookup, webhook: webhook},
              message:
                "Temporary database issue during webhook lookup. Please retry in %{s}s."
            )
        end

      _ ->
        conn
    end
  end

  defp validate_auth(nil, _methods, conn), do: not_found_response(conn)

  defp validate_auth(trigger, methods, conn) do
    case methods do
      [] -> successful_response(conn, trigger)
      _ -> check_auth(conn, methods, trigger)
    end
  end

  defp successful_response(conn, trigger) do
    assign(conn, :trigger, trigger)
  end

  defp check_auth(conn, auth_methods, trigger) do
    cond do
      valid_key?(conn, auth_methods) or valid_user?(conn, auth_methods) ->
        successful_response(conn, trigger)

      authenticated_request(conn) ->
        not_found_response(conn)

      true ->
        unauthorized_response(conn)
    end
  end

  defp authenticated_request(conn) do
    conn |> get_req_header("x-api-key") != [] or
      conn |> get_req_header("authorization") != []
  end

  defp unauthorized_response(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{"error" => "Unauthorized"})
    |> halt()
  end

  defp not_found_response(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "Webhook not found"})
    |> halt()
  end

  defp valid_key?(conn, methods) do
    Enum.any?(methods, &key_matches?(conn, &1))
  end

  defp key_matches?(
         conn,
         %WebhookAuthMethod{auth_type: :api, api_key: key}
       ) do
    get_req_header(conn, "x-api-key")
    |> Enum.any?(fn header_value ->
      Plug.Crypto.secure_compare(header_value, key)
    end)
  end

  defp key_matches?(_, _), do: false

  defp valid_user?(conn, methods) do
    Enum.any?(methods, &user_matches?(conn, &1))
  end

  defp user_matches?(conn, %WebhookAuthMethod{
         auth_type: :basic,
         username: expected_user,
         password: expected_pass
       }) do
    secure_eq = fn a, b ->
      Plug.Crypto.secure_compare(
        :crypto.hash(:sha256, a),
        :crypto.hash(:sha256, b)
      )
    end

    get_req_header(conn, "authorization")
    |> Enum.find_value(false, fn auth ->
      with [scheme, b64] <- String.split(auth, " ", parts: 2),
           true <- String.downcase(scheme) == "basic",
           {:ok, decoded} <- Base.decode64(b64),
           [user, pass] <- String.split(decoded, ":", parts: 2),
           true <- secure_eq.(user, expected_user),
           true <- secure_eq.(pass, expected_pass) do
        true
      else
        _ -> false
      end
    end)
  end

  defp user_matches?(_, _), do: false
end
