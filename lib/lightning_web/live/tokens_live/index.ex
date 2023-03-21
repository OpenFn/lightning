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
       get_tokens(socket.assigns.current_user)
     )
     |> assign(:active_menu_item, :tokens)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Personal Access Tokens")
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
       get_tokens(socket.assigns.current_user)
     )
     |> put_flash(:info, "Token created successfully")}
  end

  @impl true
  def handle_event("delete_token", %{"id" => id}, socket) do
    token = Accounts.get_token!(id).token

    Accounts.delete_api_token(token)
    |> case do
      :ok ->
        {:noreply,
         socket
         |> assign(
           :tokens,
           get_tokens(socket.assigns.current_user)
         )
         |> assign(:new_token, nil)
         |> put_flash(:info, "Token deleted successfully")}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Can't delete token")}
    end
  end

  @impl true
  def handle_event("copy", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Token copied successfully")}
  end

  @impl true
  defp mask_token(token) do
    length = String.length(token)
    masked_length = length - 10
    mask = String.duplicate("*", masked_length)

    Regex.replace(~r/^(.{#{masked_length}})/, token, mask)
    |> String.slice(195, masked_length)
  end

  defp get_tokens(user) do
    Accounts.list_api_tokens(user)
    |> Enum.map(fn ut ->
      %{
        "id" => ut.id,
        "token" => mask_token(ut.token),
        "inserted_at" => ut.inserted_at
      }
    end)
  end
end
