defmodule LightningWeb.API.MeTokenController do
  @moduledoc """
  The personal access tokens of the person the token belongs to.

  `GET /api/me/tokens` lists them, newest first and not paged, each with its
  token masked to its first and last five characters. `DELETE
  /api/me/tokens/:id` revokes one at once, on every route, and answers 204; a
  token can revoke itself, to rotate. An id that names no token of the
  person's is 404 `not_found`. Both take a personal access token or a session
  token, and refuse the service account and repo connections with 403
  `forbidden`.

  `POST /api/me/tokens` creates one and answers 201 with the whole token, which
  is never shown again. It needs a person at the keyboard: only a session token
  that has been stepped up, so any other token is 403 `forbidden`, and a
  session that hasn't is 403 `step_up_required`.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:account, :list_own_tokens} when action == :index
  plug AuthorizeAction, {:account, :create_own_token} when action == :create
  plug AuthorizeAction, {:account, :revoke_own_token} when action == :delete

  def index(conn, _params) do
    tokens = Accounts.list_api_tokens(conn.assigns.scope.actor)
    render(conn, :index, tokens: tokens)
  end

  def create(conn, _params) do
    with {:ok, token} <- Accounts.create_api_token(conn.assigns.scope.actor) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_status(:created)
      |> render(:create, token: token)
    end
  end

  def delete(conn, _params) do
    with {:ok, id} <- Request.id(Request.param(conn, "id")),
         :ok <- Accounts.revoke_api_token(conn.assigns.scope.actor, id) do
      send_resp(conn, 204, "")
    end
  end
end
