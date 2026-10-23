defmodule LightningWeb.API.NoRoute do
  @moduledoc """
  The catch-all route at the end of each JSON scope: 404 `not_found` as a
  problem document that follows `Accept` (error-format spec §5). A path the
  error format doesn't cover gets the router's own 404.
  """
  @behaviour Plug

  alias LightningWeb.API.Problem
  alias LightningWeb.API.ProblemPaths

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if ProblemPaths.member?(conn),
      do: Problem.respond(conn, Problem.new(:not_found)),
      else:
        raise(Phoenix.Router.NoRouteError,
          conn: conn,
          router: LightningWeb.Router
        )
  end
end
