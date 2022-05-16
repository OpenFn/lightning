defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    case Bodyguard.permit(
           Lightning.Accounts.Policy,
           :index,
           socket.assigns.current_user
         ) do
      :ok ->
        {:ok,
         assign(socket, :users, list_users())
         |> assign(:active_menu_item, :users),
         layout: {LightningWeb.LayoutView, "settings.html"}}

      {:error, :unauthorized} ->
        {:ok,
         put_flash(socket, :error, "You can't access that page")
         |> push_redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
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
