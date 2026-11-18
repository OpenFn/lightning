defmodule LightningWeb.API.AppMapController do
  @moduledoc """
  Serves the app map (`priv/app_map.json`) to the React frontend.

  The map is static product metadata — the same for every authenticated
  user — so no project scoping applies.
  """
  use LightningWeb, :controller

  alias Lightning.AiAssistant.AppMap

  def index(conn, _params) do
    case AppMap.fetch() do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "app_map_unavailable"})

      pages ->
        json(conn, %{pages: pages})
    end
  end
end
