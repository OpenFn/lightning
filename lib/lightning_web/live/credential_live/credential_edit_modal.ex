defmodule LightningWeb.CredentialLive.CredentialEditModal do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Credentials.Credential
  import LightningWeb.Components.Form

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
        credential={%Credential{user_id: assigns.current_user.id}}
        projects={[]}
        project={@project}
        on_save={@on_save}
        show_project_credentials={false}
      >
        <:buttons :let={changeset}>
          <%= render_slot(@cancel) %>
          <.submit_button phx-disable-with="Saving..." disabled={!changeset.valid?}>
            Save
          </.submit_button>
        </:buttons>
      </.live_component>
    </div>
    """
  end
end
