defmodule LightningWeb.API.ProblemPaths do
  @moduledoc """
  The paths whose errors before a controller runs are problem documents: every
  `/api` route but the OAuth token endpoint, `/collections` and
  `/adaptors/catalogue` (error-format spec §1). Webhooks under `/i` are not
  among them, though a body they can't read is answered with a problem document
  (§12).
  """

  @body_errors [
    Plug.Parsers.BadEncodingError,
    Plug.Parsers.ParseError,
    Plug.Parsers.RequestTooLargeError
  ]

  @spec member?(Plug.Conn.t()) :: boolean()
  def member?(%Plug.Conn{path_info: path_info}), do: problem_path?(path_info)

  @doc """
  Whether `exception`, raised while answering `conn`, is answered with a
  problem document: on every path `member?/1` covers, and on `/i/*` when it is
  a request body Lightning can't read.
  """
  @spec answers?(Plug.Conn.t(), term()) :: boolean()
  def answers?(%Plug.Conn{path_info: ["i" | _]}, %struct{})
      when struct in @body_errors,
      do: true

  def answers?(conn, _exception), do: member?(conn)

  defp problem_path?(["api", "oauth", "token" | _]), do: false
  defp problem_path?(["api" | _]), do: true
  defp problem_path?(["collections" | _]), do: true
  defp problem_path?(["adaptors", "catalogue" | _]), do: true
  defp problem_path?(_path_info), do: false
end
