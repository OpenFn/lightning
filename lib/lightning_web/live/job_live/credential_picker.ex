defmodule LightningWeb.JobLive.CredentialPicker do
  @moduledoc """
  Component allowing selecting a credential or creating a new one via a
  modal.
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form
  alias Phoenix.LiveView.JS

  attr :form, :map, required: true
  attr :disabled, :boolean, default: false
  attr :credentials, :list, required: true
  attr :on_change, :any, default: nil

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        credential_options:
          assigns.credentials |> Enum.map(&{&1.credential.name, &1.id})
      )

    ~H"""
    <div>
      <Form.label_field
        form={@form}
        field={:project_credential_id}
        title="Credential"
        tooltip="If the system you're working with requires authentication, choose a credential with login details (secrets) that will allow this job to connect. If you're not connecting to an external system you don't need a credential."
      />
      <.old_error field={@form[:project_credential_id]} />
      <Form.select_field
        form={@form}
        name={:project_credential_id}
        prompt=""
        values={@credential_options}
        disabled={@disabled}
      />

      <div :if={!@disabled} class="text-right">
        <button
          id="new-credential-button"
          type="button"
          class="link text-xs"
          phx-click="toggle_credentials_modal"
          phx-target={@myself}
        >
          New credential
        </button>
      </div>

      <.live_component
        :if={!@disabled and @show_credential_modal}
        id="new-credential-modal"
        module={LightningWeb.CredentialLive.CredentialFormComponent}
        action={:new}
        credential_type={nil}
        credential={
          %Lightning.Credentials.Credential{
            user_id: @current_user.id,
            project_credentials: [
              %Lightning.Projects.ProjectCredential{
                project_id: @project.id
              }
            ]
          }
        }
        current_user={@current_user}
        oauth_client={nil}
        oauth_clients={@oauth_clients}
        projects={[]}
        project={@project}
        on_save={
          fn credential ->
            params =
              LightningWeb.Utils.build_params_for_field(
                @form,
                :project_credential_id,
                credential.project_credentials |> Enum.at(0) |> Map.get(:id)
              )

            @on_change.(params)
          end
        }
        on_modal_close={JS.push("toggle_credentials_modal", target: @myself)}
        can_create_project_credential={!@disabled}
        return_to={@credential_modal_return_to}
      />
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       credentials: [],
       selected_project_credential_id: nil,
       show_credential_modal: false
     )}
  end

  @impl true
  def update(%{project: project} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> update(:selected_project_credential_id, fn _, %{form: form} ->
        form.source |> Ecto.Changeset.get_field(:project_credential_id)
      end)
      |> then(fn socket ->
        %{
          credentials: credentials,
          selected_project_credential_id: selected_project_credential_id
        } = socket.assigns

        selected_in_list? =
          credentials
          |> Enum.any?(&match?(%{id: ^selected_project_credential_id}, &1))

        if selected_in_list? &&
             !changed?(socket, :selected_project_credential_id) do
          socket
        else
          socket
          |> assign(
            credentials: Lightning.Projects.list_project_credentials(project)
          )
        end
      end)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_credentials_modal", _params, socket) do
    {:noreply, update(socket, :show_credential_modal, fn show -> !show end)}
  end
end
