defmodule LightningWeb.TokensLive.Modal do
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
    <div id="edit-token-modal">
      <.live_component
        module={LightningWeb.CredentialLive.FormComponent}
        id={:new}
        action={:new}
        projects={[]}
        project={@project}
        on_save={@on_save}
        show_project_tokens={false}
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
