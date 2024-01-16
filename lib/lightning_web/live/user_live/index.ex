defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

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
       put_flash(socket, :nav, :no_access)
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

  def delete_action(assigns) do
    if assigns.user.scheduled_deletion do
      ~H"""
      <span>
        <.link
          id={"cancel-deletion-#{@user.id}"}
          href="#"
          phx-click="cancel_deletion"
          phx-value-id={@user.id}
        >
          Cancel deletion
        </.link>
      </span>
      |
      <span>
        <.link
          id={"delete-now-#{@user.id}"}
          navigate={Routes.user_index_path(@socket, :delete, @user)}
        >
          Delete now
        </.link>
      </span>
      """
    else
      ~H"""
      <span>
        <.link
          id={"delete-#{@user.id}"}
          navigate={Routes.user_index_path(@socket, :delete, @user)}
        >
          Delete
        </.link>
      </span>
      """
    end
  end
end
