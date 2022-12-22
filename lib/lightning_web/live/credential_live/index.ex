defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials

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

  defp has_error?(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.any?()
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

      {:error, changeset} ->
        # must be a better way (traverse errors, get messages ...)
        cond do
          has_error?(changeset, :job_using_credential) ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Can't delete. This credential is being used by at least one job"
             )}

          true ->
            {:noreply, socket |> put_flash(:error, "Can't delete credential")}
        end
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
