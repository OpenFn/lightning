defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  import LightningWeb.UserLive.CommonComponents

  alias Lightning.Accounts
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      modal = Map.get(socket, :private, %{})[:delete_modal]

      socket =
        assign(socket,
          users: list_users(),
          active_menu_item: :users,
          user_deletion_modal: modal
        )

      {:ok, socket, layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       put_flash(socket, :nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:delete_user, nil)
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:delete_user, Accounts.get_user!(id))
  end

  @impl true
  def handle_event(
        "cancel_deletion",
        %{"id" => user_id},
        socket
      ) do
    Accounts.cancel_scheduled_deletion(user_id)

    {:noreply,
     socket
     |> put_flash(:info, "User deletion canceled")
     |> push_patch(to: ~p"/settings/users")}
  end

  defp list_users do
    Accounts.list_users()
  end
end
