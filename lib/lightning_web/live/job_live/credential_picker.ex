defmodule LightningWeb.JobLive.CredentialPicker do
  @moduledoc """
  Component allowing selecting a credential or creating a new one via a
  modal.
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

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
          class="text-indigo-400 underline underline-offset-2 hover:text-indigo-500 text-xs"
          phx-click={show_modal("new-credential-modal")}
          phx-target={@myself}
        >
          New credential
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(credentials: [], selected_project_credential_id: nil)}
  end

  @impl true
  def update(%{project_user: project_user} = assigns, socket) do
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
            credentials:
              Lightning.Projects.list_project_credentials(project_user.project)
          )
        end
      end)

    {:ok, socket}
  end
end
