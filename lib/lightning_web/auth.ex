defmodule LightningWeb.Auth do
  @moduledoc """
  Shared HTTP request authentication functions.

  Validates inbound requests against `WebhookAuthMethod` records using
  API key (`x-api-key` header) or Basic Auth (`authorization` header).
  Used by both `WebhookAuth` plug (triggers) and `ChannelProxyPlug`
  (channels).

  All comparisons use `Plug.Crypto.secure_compare/2` to prevent
  timing attacks.
  """
  import Plug.Conn, only: [get_req_header: 2]

  alias Lightning.Workflows.WebhookAuthMethod

  @doc """
  Returns true if the request's `x-api-key` header matches any
  `:api`-type auth method in the list.
  """
  def valid_key?(conn, methods) do
    Enum.any?(methods, &key_matches?(conn, &1))
  end

  @doc """
  Returns true if the request's Basic Auth credentials match any
  `:basic`-type auth method in the list.
  """
  def valid_user?(conn, methods) do
    Enum.any?(methods, &user_matches?(conn, &1))
  end

  @doc """
  Returns true if the request contains an `x-api-key` or
  `authorization` header (regardless of whether the value is correct).
  """
  def has_credentials?(conn) do
    get_req_header(conn, "x-api-key") != [] or
      get_req_header(conn, "authorization") != []
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

  defp user_matches?(conn, %WebhookAuthMethod{
         auth_type: :basic,
         username: expected_user,
         password: expected_pass
       }) do
    get_req_header(conn, "authorization")
    |> Enum.find_value(false, fn auth ->
      with [scheme, b64] <- String.split(auth, " ", parts: 2),
           true <- String.downcase(scheme) == "basic",
           {:ok, decoded} <- Base.decode64(b64),
           [user, pass] <- String.split(decoded, ":", parts: 2),
           true <- Plug.Crypto.secure_compare(user, expected_user),
           true <- Plug.Crypto.secure_compare(pass, expected_pass) do
        true
      else
        _ -> false
      end
    end)
  end

  defp user_matches?(_, _), do: false
end
