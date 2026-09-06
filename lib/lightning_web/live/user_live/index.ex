defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :ensure_admin}

  alias Lightning.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_menu_item: :users),
     layout: {LightningWeb.Layouts, :settings}}
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
    case Accounts.cancel_scheduled_deletion(user_id) do
      {:ok, _change} ->
        {:noreply,
         socket
         |> put_flash(:info, "User deletion canceled")
         |> push_navigate(to: ~p"/settings/users")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cancel user deletion failed")}
    end
  end
end
