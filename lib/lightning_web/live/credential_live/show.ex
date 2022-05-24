defmodule LightningWeb.CredentialLive.Show do
  @moduledoc """
  LiveView for viewing a single Job
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    case Bodyguard.permit(
           Lightning.Credentials.Policy,
           :show,
           %{"user_id" => socket.assigns.current_user.id},
           %{"credential_id" => id}
         ) do
      :ok ->
        {:noreply,
         socket
         |> assign(:page_title, page_title(socket.assigns.live_action))
         |> assign(:active_menu_item, :credentials)
         |> assign(
           :credential,
           Credentials.get_credential_for_user(
             id,
             socket.assigns.current_user.id
           )
         )}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You can't access that page")
         |> push_redirect(to: "/credentials")}
    end
  end

  defp page_title(:show), do: "Show Credential"
  defp page_title(:edit), do: "Edit Credential"
end
