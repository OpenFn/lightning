defmodule LightningWeb.API.AppMapController do
  @moduledoc """
  Serves the app map (`priv/app_map.json`) to the React frontend.

  The map is static product metadata, filtered per user: admin-section pages
  are omitted for non-superusers (see
  `Lightning.AiAssistant.AppMap.fetch_for/1`). No project scoping applies.
  """
  use LightningWeb, :controller

  alias Lightning.AiAssistant.AppMap

  def index(conn, _params) do
    case AppMap.fetch_for(conn.assigns.current_user) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "app_map_unavailable"})

      pages ->
        json(conn, %{pages: pages})
    end
  end
end
