defmodule LightningWeb.CredentialLive.CredentialEditModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Credentials.Credential

  @impl true
  def update(%{project: _project} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:on_save, fn credential ->
       send(self(), {:added_credential, credential})
     end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"project-#{@project.id}"}>
      <PetalComponents.Modal.modal
        max_width="lg"
        title="Create credential"
        close_modal_target={@myself}
      >
        <.live_component
          module={LightningWeb.CredentialLive.FormComponent}
          id={:new}
          action={:new}
          credential={%Credential{user_id: assigns.current_user.id}}
          projects={[]}
          project={@project}
          on_save={@on_save}
          show_project_credentials={false}
        />
      </PetalComponents.Modal.modal>
    </div>
    """
  end
end
