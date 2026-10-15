defmodule LightningWeb.API.Challenge do
  @moduledoc """
  The `WWW-Authenticate` headers a refused bearer token gets (RFC 6750 §3,
  error-format spec §9.1 and §9.2).
  """

  @type header :: {String.t(), String.t()}

  @doc "The challenge on a 401 for a token sent but refused."
  @spec invalid_token() :: header()
  def invalid_token, do: bearer(~s(error="invalid_token"))

  @doc "The challenge on a 403 for a token that lacks `grant`."
  @spec insufficient_scope(String.t()) :: header()
  def insufficient_scope(grant),
    do: bearer(~s(error="insufficient_scope", scope="#{grant}"))

  defp bearer(params), do: {"www-authenticate", "Bearer " <> params}
end
