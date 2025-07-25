defmodule LightningWeb.CredentialLive.KeychainCredentialFormComponent do
  @moduledoc """
  Form Component for working with a single KeychainCredential
  """
  use LightningWeb, :live_component

  alias Lightning.Credentials
  alias Lightning.Policies.Permissions
  alias LightningWeb.Components.NewInputs

  @valid_assigns [
    :action,
    :credentials,
    :current_user,
    :id,
    :keychain_credential,
    :on_close,
    :project,
    :project_user,
    :return_to
  ]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, available_credentials: [])}
  end

  @impl true
  def update(%{project: project, project_user: project_user} = assigns, socket) do
    changeset =
      Credentials.change_keychain_credential(assigns.keychain_credential)

    initial_assigns = Map.filter(assigns, fn {k, _} -> k in @valid_assigns end)

    available_credentials =
      if assigns.project do
        Credentials.list_credentials_for_project(assigns.project)
      else
        []
      end

    can_create =
      Permissions.can?(
        :credentials,
        :create_keychain_credential,
        assigns.current_user,
        %{project: project, project_user: project_user}
      )

    can_edit =
      assigns.keychain_credential &&
        Permissions.can?(
          :credentials,
          :edit_keychain_credential,
          assigns.project_user,
          assigns.keychain_credential
        )

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign(
       changeset: changeset,
       available_credentials: available_credentials,
       can_create: can_create,
       can_edit: can_edit
     )}
  end

  @impl true
  def handle_event("validate", %{"keychain_credential" => params}, socket) do
    changeset =
      socket.assigns.keychain_credential
      |> Credentials.change_keychain_credential(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("save", %{"keychain_credential" => params}, socket) do
    save_keychain_credential(socket, socket.assigns.action, params)
  end

  attr :id, :string
  attr :action, :atom
  attr :keychain_credential, Lightning.Credentials.KeychainCredential
  attr :project, Lightning.Projects.Project
  attr :credentials, :list, default: []
  attr :project_user, Lightning.Projects.ProjectUser
  attr :return_to, :string
  attr :can_edit, :boolean
  attr :can_create, :boolean

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs text-left">
      <Components.Credentials.credential_modal
        id={@id}
        width="xl:min-w-1/3 min-w-1/2 max-w-full"
      >
        <:title>
          <div class="flex justify-between">
            <%= if @action == :edit do %>
              Edit keychain credential
            <% else %>
              Create keychain credential
            <% end %>
          </div>
        </:title>

        <.form
          :let={f}
          for={@changeset}
          id={"keychain-credential-form-#{@keychain_credential.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="space-y-6 bg-white py-5">
            <fieldset>
              <div class="space-y-4">
                <div>
                  <NewInputs.input
                    type="text"
                    field={f[:name]}
                    label="Name"
                    placeholder="Enter keychain credential name"
                  />
                  <p class="mt-1 text-sm text-gray-500">
                    A descriptive name for this keychain credential
                  </p>
                </div>

                <div>
                  <NewInputs.input
                    type="text"
                    field={f[:path]}
                    label="JSONPath Expression"
                    placeholder="$.user_id"
                  />
                  <p class="mt-1 text-sm text-gray-500">
                    JSONPath expression to extract credential selector from run data
                  </p>
                </div>

                <div>
                  <NewInputs.input
                    type="select"
                    field={f[:default_credential_id]}
                    label="Default Credential"
                    options={
                      [{"No default credential", nil}] ++
                        Enum.map(@available_credentials, &{&1.name, &1.id})
                    }
                  />
                  <p class="mt-1 text-sm text-gray-500">
                    Credential to use when JSONPath expression doesn't match
                  </p>
                </div>
              </div>
            </fieldset>
          </div>

          <.modal_footer>
            <.button
              id={"save-keychain-credential-button-#{@keychain_credential.id || "new"}"}
              type="submit"
              theme="primary"
              disabled={!@changeset.valid?}
            >
              <%= case @action do %>
                <% :edit -> %>
                  Save Changes
                <% :new -> %>
                  Create
              <% end %>
            </.button>
            <Components.Credentials.cancel_button modal_id={@id} />
          </.modal_footer>
        </.form>
      </Components.Credentials.credential_modal>
    </div>
    """
  end

  defp save_keychain_credential(socket, :edit, params) do
    if socket.assigns.can_edit do
      case Credentials.update_keychain_credential(
             socket.assigns.keychain_credential,
             params
           ) do
        {:ok, _keychain_credential} ->
          {:noreply,
           socket
           |> put_flash(:info, "Keychain credential updated successfully")
           |> push_event("close_modal", %{id: socket.assigns.id})
           |> then(fn socket ->
             if socket.assigns[:on_close] do
               socket.assigns.on_close.()
             end

             socket
           end)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:noreply,
       socket
       |> put_flash(
         :error,
         "You are not authorized to edit this keychain credential"
       )
       |> push_event("close_modal", %{id: socket.assigns.id})}
    end
  end

  defp save_keychain_credential(socket, :new, params) do
    if socket.assigns.can_create do
      case Credentials.create_keychain_credential(
             socket.assigns.keychain_credential,
             params
           ) do
        {:ok, _keychain_credential} ->
          {:noreply,
           socket
           |> put_flash(:info, "Keychain credential created successfully")
           |> push_event("close_modal", %{id: socket.assigns.id})}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:noreply,
       socket
       |> put_flash(
         :error,
         "You are not authorized to create keychain credentials"
       )
       |> push_event("close_modal", %{id: socket.assigns.id})}
    end
  end
end
