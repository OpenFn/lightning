defmodule LightningWeb.API.AuditEventController do
  @moduledoc """
  Lists the instance's audit events, newest first, for a superuser or the
  service account with `audit:read`.

      GET /api/audit_events?item_type=project&inserted_after=2026-01-01T00:00:00Z

  Filters: `item_type`, `item_id`, `actor_id`, `event`, `inserted_after` and
  `inserted_before`. Every bad one is reported in one 400 `invalid_parameter`.
  """
  use LightningWeb, :controller

  alias Lightning.Auditing
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:audit_events, :read_audit_events}

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, filters} <-
           params |> Filters.audit_events() |> Errors.refuse_parameters() do
      page = Auditing.paginate_events(filters, Filters.page(params))
      render(conn, "index.json", page: page, filters: filters, conn: conn)
    end
  end
end
