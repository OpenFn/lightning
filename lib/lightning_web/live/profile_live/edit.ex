defmodule LightningWeb.ProfileLive.Edit do
  @moduledoc """
  LiveView for user profile page.
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Policies.{Users, Permissions}

  @impl true
  def mount(_params, session, socket) do
    authenticated_user =
      Accounts.get_user_by_session_token(session["user_token"])

    can_delete_account =
      Users
      |> Permissions.can(
        :delete_account,
        socket.assigns.current_user,
        authenticated_user
      )

    can_change_password =
      Users
      |> Permissions.can(
        :change_password,
        socket.assigns.current_user,
        authenticated_user
      )

    {:ok,
     socket
     |> assign(
       can_delete_account: can_delete_account,
       can_change_password: can_change_password
     )}
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
    if socket.assigns.can_delete_account do
      socket
      |> assign(:page_title, "User Profile")
      |> assign(:user, user)
    else
      socket
      |> assign(:page_title, "User Profile")
      |> assign(:user, socket.assigns.current_user)
      |> put_flash(:error, "You are not authorized to perform this action.")
    end
  end
end
