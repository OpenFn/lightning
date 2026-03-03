defmodule LightningWeb.ProfileLive.Edit do
  @moduledoc """
  LiveView for user profile page.
  """
  use LightningWeb, :live_view

  import LightningWeb.ProfileLive.Components

  alias Lightning.VersionControl

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      VersionControl.subscribe(socket.assigns.current_user)
    end

    {:ok, socket |> assign(:active_menu_item, :profile)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       params
     )}
  end

  @impl true
  def handle_info(
        %Lightning.VersionControl.Events.OauthTokenAdded{},
        socket
      ) do
    {:noreply,
     socket
     |> put_flash(:info, "GitHub account linked successfully")
     |> push_navigate(to: ~p"/profile")}
  end

  def handle_info(
        %Lightning.VersionControl.Events.OauthTokenFailed{},
        socket
      ) do
    {:noreply,
     socket
     |> put_flash(
       :error,
       "Oops! GitHub account failed to link. Please try again"
     )}
  end

  defp apply_action(socket, :edit, _params) do
    socket
    |> assign(:page_title, "User Profile")
    |> assign(:user, socket.assigns.current_user)
  end

  defp apply_action(socket, :delete, %{"id" => user_id}) do
    user = Lightning.Accounts.get_user!(user_id)

    can_delete_account =
      Lightning.Policies.Users
      |> Lightning.Policies.Permissions.can?(
        :delete_account,
        socket.assigns.current_user,
        user
      )

    if can_delete_account do
      modal =
        socket.router
        |> Phoenix.Router.route_info("GET", ~p"/profile", nil)
        |> Map.get(:delete_modal)

      socket
      |> assign(:page_title, "User Profile")
      |> assign(:user, user)
      |> assign(:user_deletion_modal, modal)
    else
      put_flash(socket, :error, "You can't perform this action")
      |> push_patch(to: ~p"/profile")
    end
  end
end
