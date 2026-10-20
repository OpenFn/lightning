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

  # A token that's gone (deleted in another tab) is refused like someone
  # else's, so the page doesn't crash and doesn't reveal which ids exist.
  defp apply_action(socket, :delete, %{"id" => id}) do
    current_user = socket.assigns.current_user

    with %{token: api_token} <- Accounts.get_token(id),
         true <-
           Permissions.can?(Users, :delete_api_token, current_user, api_token) do
      socket
      |> assign(:page_title, "Personal Access Tokens")
      |> assign(:token_id, id)
      |> assign(:new_token, nil)
    else
      _ -> refuse(socket)
    end
  end

  defp refuse(socket) do
    socket
    |> put_flash(:error, "You can't perform this action")
    |> push_patch(to: ~p"/profile/tokens")
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

  # Only the token whose delete modal passed the :delete action's permission
  # check can be deleted.
  def handle_event("delete_token", %{"id" => id}, socket) do
    with true <-
           socket.assigns.live_action == :delete and
             id == socket.assigns.token_id,
         %{} = token <- Accounts.get_token(id) do
      {:ok, _} = Accounts.delete_token(token)

      # A server patch keeps the flash; the client's own patch would clear it.
      {:reply, %{},
       socket
       |> assign(:tokens, get_api_tokens_for(socket.assigns.current_user))
       |> put_flash(:info, "Token deleted successfully")
       |> push_patch(to: ~p"/profile/tokens")}
    else
      _ -> {:reply, %{error: "You can't perform this action"}, refuse(socket)}
    end
  end

  defp get_api_tokens_for(user) do
    Accounts.list_api_tokens(user)
  end

  # The shape the design system's ApiToken type expects.
  defp tokens_json(tokens) do
    tokens
    |> Enum.map(fn token ->
      %{
        id: token.id,
        masked: mask_token(token),
        insertedAt: token.inserted_at,
        lastUsedAt: token.last_used_at
      }
    end)
    |> Jason.encode!()
  end

  defp mask_token(token) do
    "..." <> String.slice(token.token, -10, 10)
  end
end
