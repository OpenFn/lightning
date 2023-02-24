defmodule LightningWeb.CredentialLive.CredentialEditModal do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Credentials.Credential

  @impl true
  def update(%{project: _project} = assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="edit-credential-modal">
      <.live_component
        module={LightningWeb.CredentialLive.FormComponent}
        id={:new}
        action={:new}
        credential={
          %Credential{
            user_id: assigns.current_user.id,
            project_credentials: [
              %Lightning.Projects.ProjectCredential{project_id: @project.id}
            ]
          }
        }
        projects={[]}
        project={@project}
        on_save={@on_save}
        show_project_credentials={false}
      >
        <:button>
          <%= render_slot(@cancel) %>
        </:button>

        <:button :let={valid?} class="text-right grow">
          <LightningWeb.Components.Form.submit_button
            phx-disable-with="Saving..."
            disabled={!valid?}
          >
            Save
          </LightningWeb.Components.Form.submit_button>
        </:button>
      </.live_component>
    </div>
    """
  end
end
