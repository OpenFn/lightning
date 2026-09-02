defmodule LightningWeb.MaintenanceLive.Index do
  @moduledoc """
  Superuser-only maintenance page for on-demand operations against
  `Lightning.Adaptors`.

  Exposes two actions: "Refresh Adaptor Registry" (`refresh/0`) and
  "Refresh Adaptor Icons" (`refresh_icons/0`). Neither blocks the LiveView:
  the registry refresh is fire-and-forget on the leader node, while the icon
  refresh runs under `start_async` (the underlying call can take up to two
  minutes) and flashes its result when it completes.
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
        case Lightning.Adaptors.refresh() do
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
      {:noreply,
       socket
       |> put_flash(:info, "Icon refresh started.")
       |> start_async(:refresh_icons, fn ->
         Lightning.Adaptors.refresh_icons()
       end)}
    else
      {:noreply,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_async(:refresh_icons, {:ok, result}, socket) do
    socket =
      case result do
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
  end

  def handle_async(:refresh_icons, {:exit, reason}, socket) do
    {:noreply,
     put_flash(socket, :error, "Icon refresh failed: #{inspect(reason)}")}
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
