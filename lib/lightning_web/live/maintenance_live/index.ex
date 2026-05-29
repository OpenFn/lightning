defmodule LightningWeb.MaintenanceLive.Index do
  @moduledoc """
  Superuser-only maintenance page exposing on-demand operations against the
  `Lightning.Adaptors` supervisor (and, eventually, other facades).

  Currently exposes a single action: "Refresh Adaptor Registry", which calls
  `Lightning.Adaptors.refresh_now/0`. The call is fire-and-forget; the user
  receives a flash and the actual work happens asynchronously on the leader
  node.
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @impl true
  def mount(_params, _session, socket) do
    if superuser?(socket) do
      {:ok,
       assign(socket,
         active_menu_item: :maintenance,
         page_title: "Maintenance"
       ), layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_event("refresh_adaptors", _params, socket) do
    if superuser?(socket) do
      socket =
        case Lightning.Adaptors.refresh_now() do
          :ok ->
            put_flash(socket, :info, "Adaptor refresh queued.")

          {:error, reason} ->
            put_flash(socket, :error, "Refresh failed: #{inspect(reason)}")
        end

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  def handle_event("refresh_icons", _params, socket) do
    if superuser?(socket) do
      socket =
        case Lightning.Adaptors.refresh_icons() do
          {:ok, %{updated: updated, unchanged: unchanged}} ->
            put_flash(
              socket,
              :info,
              "Icon refresh complete — #{updated} updated, #{unchanged} unchanged."
            )

          {:error, reason} ->
            put_flash(socket, :error, "Icon refresh failed: #{inspect(reason)}")
        end

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  defp superuser?(socket) do
    Permissions.can?(
      Users,
      :access_admin_space,
      socket.assigns.current_user,
      {}
    )
  end
end
