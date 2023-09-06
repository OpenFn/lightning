defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       :credentials,
       list_credentials(socket.assigns.current_user.id)
     )
     |> assign(:active_menu_item, :credentials)}
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

  defp apply_action(socket, :delete, %{"id" => id}) do
    credential = Credentials.get_credential!(id)
    has_activity_in_projects = Credentials.has_activity_in_projects?(credential)

    socket
    |> assign(:page_title, "Credentials")
    |> assign(:credential, credential)
    |> assign(:has_activity_in_projects, has_activity_in_projects)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    credential = Credentials.get_credential!(id)

    can_delete_credential =
      Lightning.Policies.Users
      |> Lightning.Policies.Permissions.can?(
        :delete_credential,
        socket.assigns.current_user,
        credential
      )

    has_activity_in_projects = Credentials.has_activity_in_projects?(credential)

    cond do
      not can_delete_credential ->
        {:noreply,
         put_flash(socket, :error, "You can't perform this action")
         |> push_patch(to: ~p"/credentials")}

      has_activity_in_projects ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete a credential that has activities in projects"
         )}

      true ->
        Credentials.delete_credential(credential)
        |> case do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(
               :credentials,
               list_credentials(socket.assigns.current_user.id)
             )
             |> put_flash(:info, "Credential deleted successfully")
             |> push_patch(to: ~p"/credentials")}

          {:error, _changeset} ->
            {:noreply, socket |> put_flash(:error, "Can't delete credential")}
        end
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: ~p"/credentials")}
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
