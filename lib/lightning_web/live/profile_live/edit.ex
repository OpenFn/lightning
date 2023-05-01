defmodule LightningWeb.ProfileLive.Edit do
  @moduledoc """
  LiveView for user profile page.
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.{Users, Permissions}

  @impl true
  def mount(_params, _session, socket) do
    can_access_own_profile =
      Users
      |> Permissions.can(
        :access_own_profile,
        socket.assigns.current_user,
        socket.assigns.current_user
      )

    if can_access_own_profile do
      {:ok, socket |> assign(:active_menu_item, :profile)}
    else
      {:ok,
       put_flash(socket, :error, "You can't access that page")
       |> push_redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       socket.assigns.current_user
     )}
  end

  defp apply_action(socket, :edit, params) do
    socket
    |> assign(:page_title, "User Profile")
    |> assign(:user, params)
  end

  defp apply_action(socket, :delete, user) do
    socket
    |> assign(:page_title, "User Profile")
    |> assign(:user, user)
  end
end
