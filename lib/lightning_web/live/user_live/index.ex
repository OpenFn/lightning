defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.{Users, Permissions}
  alias Lightning.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, :users, list_users())
     |> assign(:active_menu_item, :users),
     layout: {LightningWeb.LayoutView, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    can_view_users =
      Users |> Permissions.can(:view_users, socket.assigns.current_user)

    if can_view_users do
      socket
      |> assign(:page_title, "Users")
      |> assign(:user, nil)
    else
      redirect(socket, to: "/") |> put_flash(:nav, :no_access)
    end
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    can_delete_users =
      Users |> Permissions.can(:delete_users, socket.assigns.current_user)

    can_delete_account =
      Users
      |> Permissions.can(
        :delete_account,
        socket.assigns.current_user,
        socket.assigns.current_user
      )

    if can_delete_users do
      socket
      |> assign(:page_title, "Users")
      |> assign(can_delete_account: can_delete_account)
      |> assign(:user, Accounts.get_user!(id))
    else
      redirect(socket, to: "/") |> put_flash(:nav, :no_access)
    end
  end

  defp list_users do
    Accounts.list_users()
  end
end
