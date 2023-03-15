defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials
  alias Lightning.Policies.{Users, Permissions}

  @impl true
  def mount(_params, _session, socket) do
    can_access_own_credentials =
      Users
      |> Permissions.can(
        :access_own_credentials,
        socket.assigns.current_user,
        socket.assigns.current_user
      )

    if can_access_own_credentials do
      {:ok,
       assign(
         socket,
         :credentials,
         list_credentials(socket.assigns.current_user.id)
       )
       |> assign(:active_menu_item, :credentials)}
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
    |> assign(:page_title, "Credentials")
    |> assign(:credential, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    credential = Credentials.get_credential!(id)

    Credentials.delete_credential(credential)
    |> case do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           :credentials,
           list_credentials(socket.assigns.current_user.id)
         )
         |> put_flash(:info, "Credential deleted successfully")}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Can't delete credential")}
    end
  end

  defp list_credentials(user_id) do
    Credentials.list_credentials_for_user(user_id)
    |> Enum.map(fn c ->
      project_names =
        Map.get(c, :projects, [])
        |> Enum.map_join(", ", fn p -> p.name end)

      Map.put(c, :project_names, project_names)
    end)
  end
end
