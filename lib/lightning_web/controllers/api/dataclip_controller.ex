defmodule LightningWeb.API.DataclipController do
  @moduledoc """
  Reads and renames a dataclip by id.

      GET   /api/dataclips/:id
      PATCH /api/dataclips/:id  {"name": "patient-sample"}

  Both answer the dataclip with its body, scrubbed of the values of every
  credential and webhook auth method that could have reached it. They are for
  people only, on a personal access token or a session token; the service
  account and repo connections are refused 403 `forbidden`.

  A dataclip's parent is the project it belongs to, found from the dataclip,
  so `LightningWeb.API.Target.in_project_of/5` answers a caller without
  permission there 403 whether the id names a dataclip, names nothing or isn't
  a UUID. No person may learn which dataclips exist, so nobody hears 404 or
  400 for the id.
  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:dataclips, :view_dataclip} when action == :show
  plug AuthorizeAction, {:dataclips, :edit_dataclip} when action == :update

  @accepted [:name]

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, dataclip} <- fetch(conn, {:dataclips, :view_dataclip}) do
      render_dataclip(conn, dataclip)
    end
  end

  @doc """
  Names the dataclip, which keeps the retention policy from wiping it, or
  removes its name with `null`. A body without `name` changes nothing.

  A name already used in the project is a `taken` entry in a 422. Refused keys
  are reported together with the name's own errors.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, dataclip} <- fetch(conn, {:dataclips, :edit_dataclip}),
         :ok <- Request.check_object(body),
         :ok <- check_body(dataclip, body),
         {:ok, dataclip} <- rename(dataclip, body, conn.assigns.current_resource) do
      render_dataclip(conn, dataclip)
    end
  end

  defp fetch(conn, permission) do
    Target.in_project_of(
      conn.assigns.scope,
      Request.param(conn, "id"),
      permission,
      &Invocation.get_dataclip_project_id/1,
      &Invocation.get_dataclip_for_project/2
    )
  end

  defp check_body(dataclip, body) do
    name_errors =
      if Map.has_key?(body, "name"),
        do:
          Errors.from_changeset(
            Invocation.change_dataclip_name(dataclip, body["name"])
          ),
        else: []

    Errors.refuse(Request.unknown_keys(body, [], @accepted) ++ name_errors)
  end

  defp rename(dataclip, %{"name" => name}, user),
    do: Invocation.update_dataclip_name(dataclip, name, user)

  defp rename(dataclip, _body, _user), do: {:ok, dataclip}

  defp render_dataclip(conn, dataclip) do
    render(conn, "show.json",
      dataclip: dataclip,
      body: Invocation.get_scrubbed_dataclip_body(dataclip),
      conn: conn
    )
  end
end
