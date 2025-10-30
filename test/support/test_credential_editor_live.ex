defmodule LightningWeb.TestCredentialEditorLive do
  @moduledoc """
  Test-only LiveView for testing credential form component edge cases
  """
  use LightningWeb, :live_view

  alias LightningWeb.CredentialLive.CredentialFormComponent

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       current_user: session["current_user"],
       project: session["project"],
       credential: session["credential"],
       return_to: session["return_to"],
       active_menu_item: :credentials,
       page_title: "Test Credential Form"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={CredentialFormComponent}
        id="test-credential-form"
        action={:edit}
        current_user={@current_user}
        project={@project}
        projects={[@project]}
        credential={@credential}
        on_save={nil}
        on_modal_close={nil}
        return_to={@return_to}
        can_create_project_credential={true}
      />
    </div>
    """
  end
end
