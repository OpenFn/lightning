defmodule LightningWeb.JobLive.CredentialPicker do
  @moduledoc """
  Component allowing selecting a credential or creating a new one via a
  modal.
  """

  use LightningWeb, :live_component

  attr :form, :map, required: true
  attr :disabled, :boolean, default: false
  attr :credentials, :list, required: true
  attr :keychain_credentials, :list, default: []
  attr :on_change, :any, default: nil

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        credential_options:
          assigns.credentials |> Enum.map(&{&1.credential.name, &1.id}),
        keychain_options:
          assigns.keychain_credentials |> Enum.map(&{&1.name, &1.id}),
        all_options:
          build_credential_options(
            assigns.credentials,
            assigns.keychain_credentials
          )
      )

    ~H"""
    <div
      phx-hook="CredentialSelector"
      data-project-field="job[project_credential_id]"
      data-keychain-field="job[keychain_credential_id]"
      id="credential-picker"
    >
      <.old_error field={@form[:project_credential_id]} />
      <.old_error field={@form[:keychain_credential_id]} />

      <.input
        type="select"
        name="credential_selector"
        id="credential_selector"
        label="Credential"
        tooltip="If the system you're working with requires authentication, choose a credential with login details (secrets) that will allow this job to connect. If you're not connecting to an external system you don't need a credential."
        options={@all_options}
        value=""
        prompt=""
        disabled={@disabled}
      />
      
    <!-- Hidden fields that get populated by JS -->
      <input
        type="hidden"
        name="job[project_credential_id]"
        value={@form[:project_credential_id].value}
      />
      <input
        type="hidden"
        name="job[keychain_credential_id]"
        value={@form[:keychain_credential_id].value}
      />

      <div :if={!@disabled} class="text-right">
        <button
          id="new-credential-button"
          type="button"
          class="link text-xs"
          phx-click="toggle_job_credential_modal"
        >
          New credential
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       credentials: [],
       keychain_credentials: [],
       selected_project_credential_id: nil,
       selected_keychain_credential_id: nil
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
      |> update(:selected_keychain_credential_id, fn _, %{form: form} ->
        form.source |> Ecto.Changeset.get_field(:keychain_credential_id)
      end)
      |> then(fn socket ->
        %{
          credentials: credentials,
          keychain_credentials: keychain_credentials,
          selected_project_credential_id: selected_project_credential_id,
          selected_keychain_credential_id: selected_keychain_credential_id
        } = socket.assigns

        project_selected_in_list? =
          credentials
          |> Enum.any?(&match?(%{id: ^selected_project_credential_id}, &1))

        keychain_selected_in_list? =
          keychain_credentials
          |> Enum.any?(&match?(%{id: ^selected_keychain_credential_id}, &1))

        if project_selected_in_list? && keychain_selected_in_list? &&
             !changed?(socket, :selected_project_credential_id) &&
             !changed?(socket, :selected_keychain_credential_id) do
          socket
        else
          socket
          |> assign(
            credentials: Lightning.Projects.list_project_credentials(project),
            keychain_credentials:
              Lightning.Credentials.list_keychain_credentials_for_project(
                project
              )
          )
        end
      end)

    {:ok, socket}
  end

  defp build_credential_options(credentials, keychain_credentials) do
    project_options = credentials |> Enum.map(&{&1.credential.name, &1.id})

    if keychain_credentials == [] do
      project_options
    else
      keychain_options = keychain_credentials |> Enum.map(&{&1.name, &1.id})
      project_options ++ [{"Keychain Credentials", keychain_options}]
    end
  end
end
