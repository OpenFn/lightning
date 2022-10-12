defmodule LightningWeb.CredentialLive.CredentialEditModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Credentials.Credential
  alias Lightning.Projects

  @impl true
 def update(%{project: _project} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"project-#{@project.id}"}>
      <PetalComponents.Modal.modal max_width="lg" title="Create credential">
        <.live_component
          module={LightningWeb.CredentialLive.FormComponent}
          id={:new}
          title="TITRE"
          action={:new}
          credential={%Credential{user_id: assigns.current_user.id}}
          projects={list_projects(assigns)}
          project={@project}
        />
      </PetalComponents.Modal.modal>
    </div>
    """
  end

  defp list_projects(assigns) do
    Projects.get_projects_for_user(assigns.current_user)
  end
end
