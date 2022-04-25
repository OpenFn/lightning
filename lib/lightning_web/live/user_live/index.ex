defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user_from_session(session, socket)

    case Bodyguard.permit(
           Lightning.Accounts.Policy,
           :index,
           socket.assigns.current_user
         ) do
      :ok ->
        {:ok,
         assign(socket, :users, list_users())
         |> assign(:active_menu_item, :users)}

      {:error, :unauthorized} ->
        {:ok,
         put_flash(socket, :error, "You can't access that page")
         |> push_redirect(to: "/")}
    end
  end

  def assign_current_user_from_session(session, socket) do
    user_token = session["user_token"]
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(socket, :current_user, user)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit User")
    |> assign(:user, Accounts.get_user!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New User")
    |> assign(:user, %User{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Users")
    |> assign(:user, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    {:ok, _} = Accounts.delete_user(user)

    {:noreply, assign(socket, :users, list_users())}
  end

  defp list_users do
    Accounts.list_users()
  end
end
