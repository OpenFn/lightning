defmodule LightningWeb.TokensLive.Index do
  @moduledoc """
  LiveView for listing and managing tokens
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       :tokens,
       Accounts.list_api_tokens(socket.assigns.current_user)
     )
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
    socket
    |> assign(:page_title, "Personal Access Tokens")
    |> assign(:token_id, id)
    |> assign(:new_token, nil)
  end

  @impl true
  def handle_event("generate_new_token", _, socket) do
    {:noreply,
     socket
     |> assign(
       :new_token,
       Accounts.generate_api_token(socket.assigns.current_user)
     )
     |> assign(
       :tokens,
       Accounts.list_api_tokens(socket.assigns.current_user)
     )
     |> put_flash(:info, "Token created successfully")}
  end

  @impl true
  def handle_event("copy", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Token copied successfully")}
  end
end
