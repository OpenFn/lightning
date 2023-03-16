defmodule LightningWeb.TokensLive.Index do
  @moduledoc """
  LiveView for listing and managing tokens
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.UserToken

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
    |> assign(:token, nil)
  end

  @impl true
  # def handle_event("delete", %{"id" => id}, socket) do
  #   token = UserToken.get_token!(id)

  #   UserToken.delete_token(token)
  #   |> case do
  #     {:ok, _} ->
  #       {:noreply,
  #        socket
  #        |> assign(
  #          :tokens,
  #          Accounts.list_api_tokens(socket.assigns.current_user)
  #        )
  #        |> put_flash(:info, "Token deleted successfully")}

  #     {:error, _changeset} ->
  #       {:noreply, socket |> put_flash(:error, "Can't delete token")}
  #   end
  # end
end
