defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.{Users, Permissions}
  alias Lightning.Accounts

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      {:ok,
       assign(socket, :users, list_users())
       |> assign(:active_menu_item, :users),
       layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       put_flash(socket, :error, "You can't access that page")
       |> push_redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:user, nil)
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:user, Accounts.get_user!(id))
  end

  def handle_event(
        "cancel_deletion",
        %{"id" => user_id},
        socket
      ) do
    user = Accounts.get_user!(user_id)
    Accounts.update_user_details(user, %{scheduled_deletion: nil})

    {:noreply,
     socket
     |> put_flash(:info, "User deletion canceled")
     |> push_navigate(to: ~p"/settings/users")}
  end

  def handle_event(
        "delete_now",
        %{"id" => user_id},
        socket
      ) do
    user = Accounts.get_user!(user_id)

    if Accounts.has_activity_in_projects?(user) do
      {:noreply,
       socket
       |> put_flash(
         :error,
         "You can't delete users that have activities in projects"
       )
       |> push_navigate(to: ~p"/settings/users")}
    else
      Accounts.delete_user(user)

      {:noreply,
       socket
       |> put_flash(:info, "User deleted")
       |> push_navigate(to: ~p"/settings/users")}
    end
  end

  defp list_users do
    Accounts.list_users()
  end

  def delete_action(assigns) do
    if assigns.user.scheduled_deletion do
      ~H"""
      <span>
        <%= link("Cancel deletion",
          to: "#",
          phx_click: "cancel_deletion",
          phx_value_id: @user.id
        ) %>
      </span>
      |
      <span>
      <%= link("Delete now",
          to: "#",
          phx_click: "delete_now",
          phx_value_id: @user.id,
          data: [
            confirm: "Are you sure you want to delete this user immediately? This action is irreversible."
          ]
        ) %>
      </span>
      """
    else
      ~H"""
      <span>
        <.link navigate={Routes.user_index_path(@socket, :delete, @user)}>
          Delete
        </.link>
      </span>
      """
    end
  end
end
