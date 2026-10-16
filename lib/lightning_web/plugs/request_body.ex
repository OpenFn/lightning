defmodule LightningWeb.Plugs.RequestBody do
  @moduledoc """
  Answers a request body Lightning can't read with a problem document on the
  paths `LightningWeb.API.ProblemPaths` covers (error-format spec §5, §9.5).

  As a module plug it wraps `Plug.Parsers`, taking `Replug`'s options, and
  answers 400 `malformed` for a body that doesn't parse and 413 `too_large`
  for one over the limit. Elsewhere those errors raise as before.

  `refuse_unparsed/2` is a function plug for the JSON pipelines: `Plug.Parsers`
  passes every content type (`pass: ["*/*"]`), so a body none of its parsers
  read arrives unfetched, and this answers it 415 `unsupported_media_type`.
  """
  @behaviour Plug

  alias LightningWeb.API.Problem
  alias LightningWeb.API.ProblemPaths
  alias Plug.Parsers.ParseError
  alias Plug.Parsers.RequestTooLargeError

  @impl true
  def init(opts), do: Replug.init(opts)

  @impl true
  def call(conn, replug) do
    Replug.call(conn, replug)
  rescue
    error in [ParseError, RequestTooLargeError] ->
      if ProblemPaths.member?(conn),
        do: refuse(conn, code(error)),
        else: reraise(error, __STACKTRACE__)
  end

  @spec refuse_unparsed(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def refuse_unparsed(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn, _),
    do: refuse(conn, :unsupported_media_type)

  def refuse_unparsed(conn, _opts), do: conn

  defp code(%ParseError{}), do: :malformed
  defp code(%RequestTooLargeError{}), do: :too_large

  defp refuse(conn, code) do
    conn
    |> Problem.respond(Problem.new(code))
    |> Plug.Conn.halt()
  end
end
