defmodule LightningWeb.API.ErrorFormat do
  @moduledoc """
  Which error format answers a request, decided by its path.

  - `:problem`: every `/api` route but the OAuth token endpoint,
    `/collections` and `/adaptors/catalogue` answer their errors with problem
    documents. Webhooks under `/i` are not among them, though a body they
    can't read is answered with a problem document.
  - `:oauth_token`: the OAuth token endpoint answers with OAuth error bodies
    (RFC 6749 §5.2), never problem documents.
  - `:phoenix`: everything else is left to Phoenix's own error rendering.
  """

  alias LightningWeb.TokenEndpointError

  @type t :: :problem | :oauth_token | :phoenix

  @body_errors [
    Plug.Parsers.BadEncodingError,
    Plug.Parsers.ParseError,
    Plug.Parsers.RequestTooLargeError
  ]

  @doc "The format a path's own errors use."
  @spec for_path(Plug.Conn.t()) :: t()
  def for_path(%Plug.Conn{path_info: path_info}), do: path_format(path_info)

  @doc """
  The format that answers `exception`, raised while answering `conn`.

  A problem path answers every raise. The token endpoint answers a raise on a
  POST, the only method it takes, when `TokenEndpointError.answers_raise?/1`
  says so, and leaves any other raise there to Phoenix. A webhook answers only
  a body it can't read.
  """
  @spec for_raise(Plug.Conn.t(), term()) :: t()
  def for_raise(%Plug.Conn{path_info: ["i" | _]}, %struct{})
      when struct in @body_errors,
      do: :problem

  def for_raise(conn, exception) do
    case {for_path(conn), conn.method} do
      {:problem, _method} ->
        :problem

      {:oauth_token, "POST"} ->
        if TokenEndpointError.answers_raise?(exception),
          do: :oauth_token,
          else: :phoenix

      _other ->
        :phoenix
    end
  end

  defp path_format(["api", "oauth", "token"]), do: :oauth_token
  defp path_format(["api", "oauth", "token" | _]), do: :phoenix
  defp path_format(["api" | _]), do: :problem
  defp path_format(["collections" | _]), do: :problem
  defp path_format(["adaptors", "catalogue" | _]), do: :problem
  defp path_format(_path_info), do: :phoenix
end
