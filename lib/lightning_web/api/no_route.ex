defmodule LightningWeb.API.NoRoute do
  @moduledoc """
  The catch-all route at the end of each JSON scope: 404 `not_found` as a
  problem document that follows `Accept`. A path the error format doesn't
  cover gets the router's own 404.
  """
  @behaviour Plug

  alias LightningWeb.API.ErrorFormat
  alias LightningWeb.API.Problem

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if ErrorFormat.for_path(conn) == :problem,
      do: Problem.respond(conn, Problem.new(:not_found)),
      else:
        raise(Phoenix.Router.NoRouteError,
          conn: conn,
          router: LightningWeb.Router
        )
  end
end
