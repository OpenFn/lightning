defmodule LightningWeb.API.Unauthenticated do
  @moduledoc """
  The one answer to a failed login on a JSON route: 401 `unauthenticated` or
  `invalid_token` (error-format spec §9.1).

  The route's scheme decides the challenge. A `:bearer` route answers
  `invalid_token` when the request sent an `Authorization` header and
  `unauthenticated` when it sent none, with the matching `Bearer` challenge. A
  `:session` route takes only the session cookie, which is not a token, so it
  always answers `unauthenticated` and names no scheme (plan D10).

  A refused permission is never a 401 (plan D9), so only auth plugs call this.
  """
  import Plug.Conn

  alias LightningWeb.API.Challenge
  alias LightningWeb.API.Problem

  @type scheme :: :bearer | :session

  @spec refuse(Plug.Conn.t(), scheme()) :: Plug.Conn.t()
  def refuse(conn, :bearer) do
    if get_req_header(conn, "authorization") == [],
      do: respond(conn, :unauthenticated, [Challenge.unauthenticated()]),
      else: respond(conn, :invalid_token, [Challenge.invalid_token()])
  end

  def refuse(conn, :session), do: respond(conn, :unauthenticated, [])

  defp respond(conn, code, headers) do
    conn
    |> Problem.respond(Problem.new(code, headers: headers))
    |> halt()
  end
end
