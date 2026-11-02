defmodule LightningWeb.API.ChannelRequestController do
  @moduledoc """
  The requests a project's channels recorded, for people: a personal access
  token or a session token. The service account and repo connections are
  refused 403 `forbidden`.

      GET /api/projects/:project_id/channel_requests?channel_id=...
      GET /api/channel_requests/:id

  Any member of the project reads them. Nobody learns from
  `GET /api/channel_requests/:id` that an id names no request: a missing id,
  one that isn't a UUID and a request in a project the caller can't access
  all answer 403 `forbidden`.
  """
  use LightningWeb, :controller

  alias Lightning.Channels
  alias Lightning.Channels.SearchParams
  alias LightningWeb.API.ChannelRequestJSON
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:channels, :access_channels}

  @access {:channels, :access_channels}

  @doc """
  Lists the project's channel requests, newest first, a page at a time,
  narrowed to one channel by `channel_id`. A `channel_id` that isn't a UUID
  answers 400 `invalid_parameter`; one that names no channel in the project
  lists nothing.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @access
           ),
         {:ok, filters} <- filters(conn) do
      page =
        Channels.list_channel_requests(
          project,
          struct(SearchParams, filters),
          Filters.page(params)
        )

      json(conn, ChannelRequestJSON.index(conn, page, filters))
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, request} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             @access,
             &Channels.get_channel_request_project_id/1,
             &get_for_project/2
           ) do
      json(conn, ChannelRequestJSON.show(request))
    end
  end

  defp filters(%{query_params: %{"channel_id" => _}} = conn) do
    with {:ok, channel_id} <- Request.id(Request.param(conn, "channel_id")),
         do: {:ok, %{channel_id: channel_id}}
  end

  defp filters(_conn), do: {:ok, %{}}

  defp get_for_project(project_id, id) do
    case Channels.get_channel_request_for_project(project_id, id) do
      nil -> {:error, :not_found}
      request -> {:ok, request}
    end
  end
end
