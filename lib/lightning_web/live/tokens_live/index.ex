defmodule LightningWeb.TokensLive.Index do
  @moduledoc """
  LiveView for listing and managing tokens
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, :tokens, get_api_tokens_for(socket.assigns.current_user))
     |> assign(:active_menu_item, :tokens)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Personal Access Tokens")
    |> assign(:new_token, nil)
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    api_token = Accounts.get_token!(id).token
    current_user = socket.assigns.current_user

    can_delete_api_token =
      Users |> Permissions.can?(:delete_api_token, current_user, api_token)

    if can_delete_api_token do
      socket
      |> assign(:page_title, "Personal Access Tokens")
      |> assign(:token_id, id)
      |> assign(:new_token, nil)
    else
      put_flash(socket, :error, "You can't perform this action")
      |> push_patch(to: ~p"/profile/tokens")
    end
  end

  @impl true
  def handle_event("generate_new_token", _, socket) do
    {:noreply,
     socket
     |> assign(
       :new_token,
       Accounts.generate_api_token(socket.assigns.current_user)
     )
     |> assign(:tokens, get_api_tokens_for(socket.assigns.current_user))
     |> put_flash(:info, "Token created successfully")}
  end

  @impl true
  def handle_event("copy", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Token copied successfully")}
  end

  defp get_api_tokens_for(user) do
    Accounts.list_api_tokens(user)
  end

  defp mask_token(token) do
    "..." <> String.slice(token.token, -10, 10)
  end
end
