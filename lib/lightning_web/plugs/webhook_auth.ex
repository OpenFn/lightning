defmodule LightningWeb.Plugs.WebhookAuth do
  @moduledoc """
  A Plug to authenticate and authorize requests based on paths starting with '/i/'.
  It verifies the presence of correct API keys or Basic Authentication credentials.
  """
  use LightningWeb, :controller

  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows
  alias Lightning.Workflows.WebhookAuthMethod

  require OpenTelemetry.Tracer

  @doc """
  Initializes the options.
  """
  def init(opts), do: opts

  @doc """
  Handles the incoming HTTP request and performs authentication and authorization checks
  based on paths starting with `/i/`.

  ## Details
  This function is the entry point for the `WebhookAuth` plug. It first checks if
  the request path starts with `/i/` to determine whether the request should be processed
  by this plug.

  If the path matches, it then extracts the `webhook` part from the request path and
  runs to fetch the corresponding `trigger` using the `fetch_trigger` function.

  If a valid `trigger` is found, the function proceeds to validate the authentication
  of the request using the `validate_auth` function.

  In case the `trigger` is not found, or the path does not start with `/i/`, the function
  returns a 404 Not Found response with a JSON error message indicating that the webhook
  is not found.

  ## Parameters
  - `conn`: The connection struct representing the incoming HTTP request.
  - `_opts`: A set of options, not used in this function but is a mandatory parameter as per
     Plug specification.

  ## Returns
  - A connection struct representing the outgoing response, which can be a successful
    response, an unauthorized response, or a not found response, based on the evaluation
    of the above-mentioned conditions.

  ## Examples
  Assuming a request with the path `/i/some_webhook`:

  ### Webhook Found and Authenticated

      iex> LightningWeb.Plugs.WebhookAuth.call(conn, [])
      %Plug.Conn{status: 200, ...}

      iex> LightningWeb.Plugs.WebhookAuth.call(conn, [])
      %Plug.Conn{status: 404, ...}
  """
  def call(conn, _opts) do
    case conn.path_info do
      ["i", webhook] ->
        trigger =
          Workflows.get_webhook_trigger(webhook,
            include: [:workflow, :edges]
          )

        validate_auth(trigger, conn)

      _ ->
        conn
    end
  end

  defp validate_auth(nil, conn), do: not_found_response(conn)

  defp validate_auth(trigger, conn) do
    case WebhookAuthMethods.list_for_trigger(trigger) do
      [] -> successful_response(conn, trigger)
      methods -> check_auth(conn, methods, trigger)
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
         username: username,
         password: password
       }) do
    encoded = "Basic " <> Base.encode64("#{username}:#{password}")
    conn |> get_req_header("authorization") |> Enum.member?(encoded)
  end

  defp user_matches?(_, _), do: false
end
