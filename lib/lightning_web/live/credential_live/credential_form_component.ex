defmodule LightningWeb.CredentialLive.CredentialFormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.Credentials
  alias Lightning.OauthClients
  alias LightningWeb.Components.NewInputs
  alias LightningWeb.CredentialLive.GenericOauthComponent
  alias LightningWeb.CredentialLive.Helpers

  attr :from_collab_editor, :boolean,
    default: false,
    doc:
      "When true, shows Advanced button to access credential type picker from collaborative editor"

  @impl true
  def mount(%{assigns: init_assigns} = socket) do
    allow_credential_transfer =
      Application.fetch_env!(:lightning, LightningWeb)
      |> Keyword.get(:allow_credential_transfer)

    mount_assigns = %{
      on_save: nil,
      on_modal_close: nil,
      scopes: [],
      scopes_changed: false,
      sandbox_changed: false,
      schema: false,
      project: nil,
      available_projects: [],
      selected_projects: [],
      workflows_using_credentials: %{},
      oauth_clients: [],
      allow_credential_transfer: allow_credential_transfer,
      current_tab: "main",
      credential_environments: [%{name: "main"}],
      credential_bodies: %{"main" => %{}},
      original_environment_names: [],
      environment_name_error: nil,
      from_collab_editor: false,
      came_from_advanced_picker: false,
      show_modal: true
    }

    {:ok,
     socket
     |> assign(mount_assigns)
     |> assign(init_assigns: init_assigns)
     |> assign(mount_assigns: mount_assigns)}
  end

  @impl true
  def update(%{current_tab: tab}, socket) do
    {:ok, assign(socket, current_tab: tab)}
  end

  def update(%{credential_bodies: bodies}, socket) do
    {:ok, assign(socket, credential_bodies: bodies)}
  end

  def update(assigns, socket) do
    assigns =
      if socket.assigns[:credential] && socket.assigns.credential.schema &&
           assigns[:credential] && !assigns.credential.schema do
        updated_credential = %{
          assigns.credential
          | schema: socket.assigns.credential.schema
        }

        Map.put(assigns, :credential, updated_credential)
      else
        assigns
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assigns_for_action()
     |> assign_new(:component_assigns, fn -> assigns end)}
  end

  @impl true
  def handle_event("validate", %{"credential" => credential_params}, socket) do
    body = Map.get(credential_params, "body", %{})

    updated_bodies =
      Map.put(socket.assigns.credential_bodies, socket.assigns.current_tab, body)

    changeset =
      Credentials.change_credential(
        socket.assigns.credential,
        credential_params |> Map.put("schema", socket.assigns.schema)
      )
      |> Map.put(:action, :validate)

    available_projects =
      Helpers.filter_available_projects(
        socket.assigns.projects,
        socket.assigns.selected_projects
      )

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> assign(credential_bodies: updated_bodies)
     |> assign(:available_projects, available_projects)
     |> assign(selected_project: nil)}
  end

  def handle_event("api_version", %{"api_version" => version}, socket) do
    {:noreply, assign(socket, api_version: version)}
  end

  def handle_event("schema_selected", %{"selected" => type} = params, socket) do
    schema_selection_form = to_form(params)

    client =
      Enum.find(socket.assigns.oauth_clients, nil, fn client ->
        client.id == type
      end)

    schema = if client, do: "oauth", else: type

    credential = %{socket.assigns.credential | schema: schema}

    changeset =
      Credentials.change_credential(credential, %{schema: schema})

    {:noreply,
     socket
     |> assign(
       credential: credential,
       changeset: changeset,
       schema: schema,
       selected_oauth_client: client,
       schema_selection_form: schema_selection_form
     )}
  end

  def handle_event("schema_selected", %{"_target" => ["selected"]}, socket) do
    {:noreply, socket}
  end

  def handle_event("change_page", _, socket) do
    {:noreply, socket |> assign(page: :second)}
  end

  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :current_tab, tab)}
  end

  def handle_event("add_environment", _, socket) do
    if length(socket.assigns.credential_environments) >= 5 do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Maximum of 5 environments allowed per credential"
       )}
    else
      existing_names =
        Enum.map(socket.assigns.credential_environments, & &1.name)

      tab_name = generate_untitled_name(existing_names)

      new_environments =
        (socket.assigns.credential_environments ++ [%{name: tab_name}])
        |> sort_environments()

      new_bodies = Map.put(socket.assigns.credential_bodies, tab_name, %{})

      {:noreply,
       socket
       |> assign(credential_environments: new_environments)
       |> assign(credential_bodies: new_bodies)
       |> assign(current_tab: tab_name)}
    end
  end

  def handle_event("update_environment_name", %{"value" => new_name}, socket) do
    old_name = socket.assigns.current_tab
    new_name = String.downcase(String.trim(new_name))

    cond do
      new_name == "" ->
        {:noreply,
         assign(socket,
           environment_name_error: "Environment name cannot be empty"
         )}

      not (new_name =~ ~r/^[a-z0-9][a-z0-9_-]{0,31}$/) ->
        {:noreply,
         assign(socket,
           environment_name_error:
             "Must be lowercase alphanumeric with hyphens or underscores (max 32 chars)"
         )}

      Enum.any?(
        socket.assigns.credential_environments,
        &(&1.name == new_name and &1.name != old_name)
      ) ->
        {:noreply,
         assign(socket,
           environment_name_error: "Environment '#{new_name}' already exists"
         )}

      true ->
        new_environments =
          Enum.map(socket.assigns.credential_environments, fn env ->
            if env.name == old_name, do: %{name: new_name}, else: env
          end)

        old_body = Map.get(socket.assigns.credential_bodies, old_name, %{})

        new_bodies =
          socket.assigns.credential_bodies
          |> Map.delete(old_name)
          |> Map.put(new_name, old_body)

        {:noreply,
         socket
         |> assign(credential_environments: new_environments)
         |> assign(credential_bodies: new_bodies)
         |> assign(current_tab: new_name)
         |> assign(environment_name_error: nil)}
    end
  end

  def handle_event("delete_environment", %{"environment" => env_name}, socket) do
    if length(socket.assigns.credential_environments) <= 1 do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Cannot delete the last environment. A credential must have at least one environment."
       )}
    else
      new_environments =
        Enum.reject(
          socket.assigns.credential_environments,
          &(&1.name == env_name)
        )

      new_bodies = Map.delete(socket.assigns.credential_bodies, env_name)

      new_current_tab =
        if socket.assigns.current_tab == env_name do
          List.first(new_environments).name
        else
          socket.assigns.current_tab
        end

      {:noreply,
       socket
       |> assign(credential_environments: new_environments)
       |> assign(credential_bodies: new_bodies)
       |> assign(current_tab: new_current_tab)}
    end
  end

  def handle_event("show_advanced_picker", _params, socket) do
    {:noreply,
     assign(socket,
       page: :advanced_picker,
       original_credential_schema: socket.assigns.credential.schema
     )}
  end

  def handle_event(
        "select_credential_type_option",
        %{"key" => key} = params,
        socket
      ) do
    type = Map.get(params, "type", "")

    {:noreply,
     assign(socket,
       selected_credential_type: key,
       selected_credential_type_type: type
     )}
  end

  def handle_event("continue_from_advanced_picker", _params, socket) do
    key = socket.assigns.selected_credential_type
    type = socket.assigns[:selected_credential_type_type]

    if is_nil(key) do
      {:noreply, socket}
    else
      case {key, type} do
        {"keychain", _} ->
          keychain_credential = %Lightning.Credentials.KeychainCredential{
            project_id: socket.assigns.project.id,
            created_by_id: socket.assigns.current_user.id
          }

          keychain_changeset =
            Credentials.change_keychain_credential(keychain_credential)

          available_credentials_for_keychain =
            if socket.assigns.project do
              Credentials.list_credentials(socket.assigns.project)
            else
              []
            end

          {:noreply,
           assign(socket,
             page: :keychain,
             keychain_credential: keychain_credential,
             keychain_changeset: keychain_changeset,
             available_credentials_for_keychain:
               available_credentials_for_keychain,
             came_from_advanced_picker: true
           )}

        {_, "oauth"} ->
          oauth_client = Enum.find(socket.assigns.oauth_clients, &(&1.id == key))
          credential = %{socket.assigns.credential | schema: "oauth"}

          if socket.assigns[:from_collab_editor] do
            send(self(), {:update_credential_schema, "oauth"})
            send(self(), {:update_selected_credential_type, key})
          end

          {:noreply,
           socket
           |> assign(
             credential: credential,
             schema: "oauth",
             oauth_client: oauth_client,
             selected_oauth_client: oauth_client,
             came_from_advanced_picker: true
           )
           |> assigns_for_action()
           |> assign(page: :second)}

        {schema, _} ->
          credential = %{socket.assigns.credential | schema: schema}

          if socket.assigns[:from_collab_editor] do
            send(self(), {:update_credential_schema, schema})
            send(self(), {:update_selected_credential_type, key})
          end

          {:noreply,
           socket
           |> assign(
             credential: credential,
             schema: schema,
             came_from_advanced_picker: true
           )
           |> assigns_for_action()
           |> assign(page: :second)}
      end
    end
  end

  def handle_event("cancel_advanced_picker", _params, socket) do
    if socket.assigns[:from_collab_editor] do
      send(self(), :clear_credential_page)
    end

    {:noreply, assign(socket, page: :second)}
  end

  def handle_event("back_to_advanced_picker_from_second", _params, socket) do
    original_schema =
      Map.get(socket.assigns, :original_credential_schema, nil)

    credential = %{socket.assigns.credential | schema: original_schema}

    {:noreply,
     assign(socket,
       page: :advanced_picker,
       came_from_advanced_picker: false,
       credential: credential,
       selected_credential_type: nil,
       selected_credential_type_type: nil
     )}
  end

  def handle_event("back_to_advanced_picker_from_keychain", _params, socket) do
    {:noreply,
     assign(socket,
       page: :advanced_picker,
       came_from_advanced_picker: false,
       keychain_credential: nil,
       keychain_changeset: nil,
       selected_credential_type: nil,
       selected_credential_type_type: nil
     )}
  end

  def handle_event(
        "validate_keychain",
        %{"keychain_credential" => params},
        socket
      ) do
    changeset =
      socket.assigns.keychain_credential
      |> Credentials.change_keychain_credential(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, keychain_changeset: changeset)}
  end

  def handle_event("save_keychain", %{"keychain_credential" => params}, socket) do
    case Credentials.create_keychain_credential(
           socket.assigns.keychain_credential,
           params
         ) do
      {:ok, keychain_credential} ->
        if socket.assigns[:on_save] do
          socket.assigns[:on_save].(keychain_credential)
        end

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, keychain_changeset: changeset)}
    end
  end

  def handle_event(
        "select_project",
        %{"project_id" => project_id},
        socket
      ) do
    {:noreply, socket |> assign(selected_project: project_id)}
  end

  def handle_event("add_selected_project", %{"project_id" => project_id}, socket) do
    {:noreply,
     socket
     |> assign(
       Helpers.select_project(
         project_id,
         socket.assigns.projects,
         socket.assigns.available_projects,
         socket.assigns.selected_projects
       )
     )
     |> assign(selected_project: nil)}
  end

  def handle_event(
        "remove_selected_project",
        %{"project_id" => project_id},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       Helpers.unselect_project(
         project_id,
         socket.assigns.projects,
         socket.assigns.selected_projects
       )
     )}
  end

  def handle_event("save", %{"credential" => credential_params}, socket) do
    if socket.assigns.can_create_project_credential do
      save_with_authorization(socket, credential_params)
    else
      socket =
        socket
        |> put_flash(:error, "You are not authorized to perform this action.")

      socket =
        if socket.assigns.return_to do
          push_navigate(socket, to: socket.assigns.return_to)
        else
          socket
        end

      {:noreply, socket}
    end
  end

  defp save_with_authorization(socket, credential_params) do
    updated_bodies = parse_credential_body(credential_params, socket)

    credential_bodies_list = build_credential_bodies_list(socket, updated_bodies)

    environments_to_delete = get_environments_to_delete(socket)

    project_credentials =
      Helpers.prepare_projects_associations(
        socket.assigns.changeset,
        socket.assigns.selected_projects,
        :project_credentials
      )

    final_params =
      credential_params
      |> Map.put("project_credentials", project_credentials)
      |> Map.put("credential_bodies", credential_bodies_list)
      |> Map.put("delete_environments", environments_to_delete)
      |> maybe_put_oauth_client_id(socket.assigns.selected_oauth_client)

    save_credential(socket, socket.assigns.action, final_params)
  end

  defp parse_credential_body(%{"body" => body_string}, socket)
       when is_binary(body_string) do
    parsed_body = parse_json_or_original(body_string)

    Map.put(
      socket.assigns.credential_bodies,
      socket.assigns.current_tab,
      parsed_body
    )
  end

  defp parse_credential_body(%{"body" => body_map}, socket)
       when is_map(body_map) do
    case Map.get(body_map, socket.assigns.current_tab) do
      nil ->
        socket.assigns.credential_bodies

      env_body_string when is_binary(env_body_string) ->
        parsed_body = parse_json_or_empty(env_body_string)

        Map.put(
          socket.assigns.credential_bodies,
          socket.assigns.current_tab,
          parsed_body
        )

      env_body_map when is_map(env_body_map) ->
        Map.put(
          socket.assigns.credential_bodies,
          socket.assigns.current_tab,
          env_body_map
        )
    end
  end

  defp parse_credential_body(_params, socket) do
    socket.assigns.credential_bodies
  end

  defp parse_json_or_original(string) do
    case Jason.decode(string) do
      {:ok, decoded} -> decoded
      {:error, _} -> string
    end
  end

  defp parse_json_or_empty(string) do
    case Jason.decode(string) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end

  defp build_credential_bodies_list(socket, updated_bodies) do
    Enum.map(socket.assigns.credential_environments, fn env ->
      body = Map.get(updated_bodies, env.name, %{})
      %{"name" => env.name, "body" => body}
    end)
  end

  defp get_environments_to_delete(%{assigns: %{action: :edit}} = socket) do
    current_names = Enum.map(socket.assigns.credential_environments, & &1.name)
    socket.assigns.original_environment_names -- current_names
  end

  defp get_environments_to_delete(_socket), do: []

  @impl true
  def render(%{page: :first} = assigns) do
    assigns =
      assigns
      |> assign_new(:schema_selection_form, fn ->
        to_form(%{"selected" => nil})
      end)

    ~H"""
    <div class="text-xs text-left">
      <Components.Credentials.credential_modal
        id={@id}
        width="xl:min-w-1/3 min-w-1/2 max-w-full"
        show={Map.get(assigns, :show_modal, true)}
        {if @on_modal_close, do: %{on_modal_close: @on_modal_close}, else: %{}}
      >
        <:title>
          <%= if @action in [:edit] do %>
            Edit a credential
          <% else %>
            Add a credential
          <% end %>
        </:title>
        <div class="container mx-auto">
          <.form
            id="credential-schema-picker"
            for={@schema_selection_form}
            phx-target={@myself}
            phx-change="schema_selected"
          >
            <div class="grid grid-cols-2 md:grid-cols-4 sm:grid-cols-3 gap-4 overflow-auto max-h-99">
              <div
                :for={{name, key, logo, _id} <- @type_options}
                class="flex items-center p-2"
              >
                <.input
                  type="radio"
                  field={@schema_selection_form[:selected]}
                  value={key}
                  checked={@schema_selection_form[:selected].value == key}
                  id={"credential-schema-picker_selected_#{key}"}
                />
                <LightningWeb.Components.Form.label_field
                  form={@schema_selection_form}
                  field={:selected}
                  for={"credential-schema-picker_selected_#{key}"}
                  title={name}
                  logo={logo}
                  class="ml-3 block text-sm font-medium text-gray-700"
                  value={key}
                />
              </div>
            </div>
          </.form>
        </div>
        <.modal_footer>
          <Components.Credentials.cancel_button
            id="cancel-credential-type-picker"
            modal_id={@id}
            {if @on_modal_close, do: %{on_modal_close: @on_modal_close}, else: %{}}
          />
          <.button
            type="button"
            theme="primary"
            disabled={!@schema}
            phx-click="change_page"
            phx-target={@myself}
          >
            Configure credential
          </.button>
        </.modal_footer>
      </Components.Credentials.credential_modal>
    </div>
    """
  end

  def render(%{page: :second} = assigns) do
    current_body = Map.get(assigns.credential_bodies, assigns.current_tab, %{})
    assigns = assign(assigns, :current_body, current_body)

    ~H"""
    <div class="text-left mt-10 sm:mt-0">
      <Components.Credentials.credential_modal
        id={@id}
        width="xl:min-w-1/3 min-w-1/2 w-[600px]"
        show={Map.get(assigns, :show_modal, true)}
        {if @on_modal_close, do: %{on_modal_close: @on_modal_close}, else: %{}}
      >
        <:title>
          <%= if @action in [:edit] do %>
            Edit {@credential.name || "credential"}
          <% else %>
            Create {format_schema_name(@schema)} credential
          <% end %>
        </:title>

        <LightningWeb.Components.Oauth.missing_client_warning :if={
          @schema == "oauth" and !@selected_oauth_client
        } />

        <.form
          :let={f}
          for={@changeset}
          id={"credential-form-#{@credential.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <div class="space-y-2 border border-gray-200 rounded-md p-4">
            <div>
              <h3 class="text-normal font-semibold text-gray-900">
                Credential identity
              </h3>
              <p class="text-xs text-gray-500 mt-1">
                Basic information that applies to all environments
              </p>
            </div>
            <div class="grid grid-cols-1 gap-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:name]}
                  label="Credential Name"
                />
              </div>
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:external_id]}
                  label="External ID"
                />
                <p class="text-xs text-gray-500 mt-1">
                  Optional identifier for external systems
                </p>
              </div>
            </div>
          </div>

          <div class="space-y-2 border border-gray-200 rounded-md p-4">
            <div>
              <h3 class="text-normal font-semibold text-gray-900">
                Credential environments
              </h3>
              <p class="text-xs text-gray-500 mt-1">
                Different credential values for each environment (dev, staging, production, etc.)
              </p>
            </div>

            <div class="border-b border-gray-200">
              <div class="flex space-x-4">
                <button
                  :for={env <- @credential_environments}
                  type="button"
                  phx-click="change_tab"
                  phx-value-tab={env.name}
                  phx-target={@myself}
                  class={[
                    "pb-4 px-1 border-b-2 font-medium text-sm transition-all whitespace-nowrap",
                    if @current_tab == env.name do
                      "border-indigo-500 text-indigo-600"
                    else
                      "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                    end
                  ]}
                >
                  {env.name}
                </button>

                <span
                  id="add-environment-button-wrapper"
                  phx-hook="Tooltip"
                  data-placement="top"
                  aria-label={
                    if length(@credential_environments) >= 5,
                      do: "Maximum of 5 environments reached",
                      else: "Add new environment"
                  }
                >
                  <button
                    id="add-environment-button"
                    type="button"
                    phx-click="add_environment"
                    phx-target={@myself}
                    disabled={length(@credential_environments) >= 5}
                    class={[
                      "pb-4 px-1 transition-colors",
                      if(length(@credential_environments) >= 5,
                        do: "text-gray-300 cursor-not-allowed",
                        else: "text-gray-400 hover:text-gray-600 cursor-pointer"
                      )
                    ]}
                  >
                    <.icon name="hero-plus" class="h-5 w-5" />
                  </button>
                </span>
              </div>
            </div>

            <div
              :for={env <- @credential_environments}
              :if={@current_tab == env.name}
            >
              <div class="mb-6">
                <NewInputs.input
                  id="environment-name-input"
                  type="text"
                  name="value"
                  required={true}
                  value={env.name}
                  label="Environment name"
                  phx-change="update_environment_name"
                  phx-target={@myself}
                  phx-debounce="300"
                  placeholder="e.g., production, staging, development, test, qa"
                  tooltip={get_environment_tooltip(@schema)}
                  errors={
                    if @environment_name_error,
                      do: [@environment_name_error],
                      else: []
                  }
                />
              </div>
              <div>
                <%= if @schema == "oauth" do %>
                  <.live_component
                    module={GenericOauthComponent}
                    id={"generic-oauth-component-#{@credential.id || "new"}-#{env.name}"}
                    parent_id={@id}
                    action={@action}
                    selected_client={@selected_oauth_client}
                    changeset={@changeset}
                    credential={@credential}
                    projects={@projects}
                    users={@users}
                    on_save={@on_save}
                    allow_credential_transfer={@allow_credential_transfer}
                    return_to={@return_to}
                    modal_id={@id}
                    on_modal_close={@on_modal_close}
                    credential_environments={@credential_environments}
                    credential_bodies={@credential_bodies}
                    current_tab={@current_tab}
                  />
                <% else %>
                  <Components.Credentials.form_component
                    :let={{fieldset, _valid?}}
                    id={@credential.id || "new"}
                    form={f}
                    type={@schema}
                    current_body={@current_body}
                  >
                    {fieldset}
                  </Components.Credentials.form_component>
                <% end %>
              </div>

              <div :if={length(@credential_environments) > 1} class="space-y-4">
                <div class="border-t border-gray-200"></div>
                <button
                  type="button"
                  phx-click="delete_environment"
                  phx-value-environment={@current_tab}
                  phx-target={@myself}
                  data-confirm={"Are you sure you want to delete the #{@current_tab} environment?"}
                  class="inline-flex items-center text-sm text-gray-500 hover:text-red-600 transition-colors"
                >
                  <.icon name="hero-trash" class="h-4 w-4 mr-1.5" />
                  Delete environment
                </button>
              </div>
            </div>
          </div>

          <div class="space-y-2 border border-gray-200 rounded-md p-4">
            <div>
              <h3 class="text-normal font-semibold text-gray-900">
                Projects access
              </h3>
              <p class="text-xs text-gray-500 mt-1">
                Select projects that can use this credential
              </p>
            </div>
            <Components.Credentials.projects_picker
              id={@credential.id || "new"}
              type={:credential}
              available_projects={@available_projects}
              selected_projects={@selected_projects}
              projects={@projects}
              selected={@selected_project}
              workflows_using_credentials={@workflows_using_credentials}
              phx_target={@myself}
            />
          </div>

          <div
            :if={@action == :edit and @allow_credential_transfer}
            class="space-y-2 border border-gray-200 rounded-md p-4"
          >
            <div>
              <h3 class="text-normal font-semibold text-gray-900">
                Transfer Ownership
              </h3>
              <p class="text-xs text-gray-500 mt-1">
                Transfer this credential to another user
              </p>
            </div>
            <Components.Credentials.credential_transfer form={f} users={@users} />
          </div>

          <.modal_footer class="sm:flex sm:flex-row justify-between items-center gap-3">
            <%= if @from_collab_editor and not @came_from_advanced_picker do %>
              <button
                type="button"
                phx-click="show_advanced_picker"
                phx-target={@myself}
                class="text-primary-600 hover:text-primary-700 text-sm font-medium underline focus:outline-none"
              >
                Advanced
              </button>
            <% else %>
              <div></div>
            <% end %>
            <div class="flex gap-2">
              <%= if @from_collab_editor and @came_from_advanced_picker do %>
                <.button
                  type="button"
                  phx-click="back_to_advanced_picker_from_second"
                  phx-target={@myself}
                  theme="secondary"
                >
                  Back
                </.button>
              <% else %>
                <Components.Credentials.cancel_button
                  modal_id={@id}
                  {if @on_modal_close, do: %{on_modal_close: @on_modal_close}, else: %{}}
                >
                  {if @from_collab_editor, do: "Back", else: "Cancel"}
                </Components.Credentials.cancel_button>
              <% end %>
              <.button
                id={"save-credential-button-#{@credential.id || "new"}"}
                type="submit"
                theme="primary"
                disabled={!@changeset.valid? or @scopes_changed or @sandbox_changed}
              >
                Save Credential
              </.button>
            </div>
          </.modal_footer>
        </.form>
      </Components.Credentials.credential_modal>
    </div>
    """
  end

  def render(%{page: :advanced_picker} = assigns) do
    assigns =
      assigns
      |> assign(
        :filtered_type_options,
        assigns.type_options
        |> Enum.filter(fn {_name, key, _logo, type} ->
          key in ["raw", "keychain"] or type == "oauth"
        end)
        |> Enum.sort_by(fn {name, key, _logo, type} ->
          cond do
            type == "oauth" -> {0, String.downcase(name)}
            key == "raw" -> {1, ""}
            key == "keychain" -> {2, ""}
          end
        end)
      )
      |> assign(
        :selected_credential_type,
        assigns[:selected_credential_type] || nil
      )

    ~H"""
    <div class="text-left" phx-mounted={JS.transition("fade-in-scale", time: 200)}>
      <Components.Credentials.credential_modal
        id={@id}
        width="xl:min-w-1/3 min-w-1/2 w-[600px]"
        show={Map.get(assigns, :show_modal, true)}
        {if @on_modal_close, do: %{on_modal_close: @on_modal_close}, else: %{}}
      >
        <:title>Advanced setup</:title>

        <div class="space-y-6">
          <p class="text-gray-700 leading-relaxed">
            Create your own credential, or reference a value from a Keychain credential.
          </p>

          <div>
            <h3 class="text-sm font-medium text-gray-500 mb-4">
              Select credential type:
            </h3>
            <ul class="space-y-1">
              <li :for={{name, key, logo, type} <- @filtered_type_options}>
                <button
                  type="button"
                  phx-click="select_credential_type_option"
                  phx-value-key={key}
                  phx-value-type={type}
                  phx-target={@myself}
                  class={[
                    "w-full flex items-start gap-4 p-3 rounded-lg transition-colors text-left",
                    if(@selected_credential_type == key,
                      do: "bg-primary-50 border-2 border-primary-500",
                      else: "hover:bg-gray-50 border-2 border-transparent"
                    )
                  ]}
                >
                  <img src={logo} alt="" class="w-10 h-10 rounded shrink-0" />
                  <div class="flex-1 min-w-0">
                    <h4 class="text-base font-medium text-gray-900">{name}</h4>
                    <p class="text-sm text-gray-500 mt-0.5">
                      {get_credential_description(key, type)}
                    </p>
                  </div>
                </button>
              </li>
            </ul>
          </div>
        </div>

        <.modal_footer>
          <.button
            type="button"
            phx-click="continue_from_advanced_picker"
            phx-target={@myself}
            theme="primary"
            disabled={is_nil(@selected_credential_type)}
          >
            Continue
          </.button>
          <.button
            type="button"
            phx-click="cancel_advanced_picker"
            phx-target={@myself}
            theme="secondary"
          >
            Back
          </.button>
        </.modal_footer>
      </Components.Credentials.credential_modal>
    </div>
    """
  end

  def render(%{page: :keychain} = assigns) do
    ~H"""
    <div>
      <Components.Credentials.keychain_credential_form
        id={@id}
        keychain_credential={@keychain_credential}
        keychain_changeset={@keychain_changeset}
        available_credentials={@available_credentials_for_keychain}
        myself={@myself}
        action={:new}
        from_collab_editor={true}
        on_validate="validate_keychain"
        on_submit="save_keychain"
        on_back={
          Phoenix.LiveView.JS.push("back_to_advanced_picker_from_keychain",
            target: @myself
          )
        }
        on_modal_close={@on_modal_close}
        show_modal={Map.get(assigns, :show_modal, true)}
      />
    </div>
    """
  end

  defp get_environment_tooltip("oauth") do
    "Environment names organize OAuth authorizations by deployment stage. Each environment can have separate OAuth tokens for different accounts or apps."
  end

  defp get_environment_tooltip(_) do
    "Environment names organize credential configurations by deployment stage. When workflows run in sandbox projects (e.g., env: 'staging'), they automatically use the matching credential environment. Choose names that align with your project environments: 'production' for live systems, 'staging' for testing, 'development' for local work. Consistent naming ensures the right secrets are used in each environment."
  end

  defp get_type_options(schemas_path) do
    schemas_options =
      Path.wildcard("#{schemas_path}/*.json")
      |> Enum.map(fn p ->
        name = p |> Path.basename() |> String.replace(".json", "")

        image_path =
          Routes.static_path(
            LightningWeb.Endpoint,
            "/images/adaptors/#{name}-square.png"
          )

        {name, name, image_path, nil}
      end)

    schemas_options
    |> Enum.reject(fn {_, name, _, _} ->
      name in ["googlesheets", "gmail", "collections"]
    end)
    |> Enum.concat([
      {"Raw JSON", "raw",
       Routes.static_path(
         LightningWeb.Endpoint,
         "/images/raw.png"
       ), nil},
      {"Keychain", "keychain",
       Routes.static_path(
         LightningWeb.Endpoint,
         "/images/keychain.png"
       ), nil}
    ])
    |> Enum.sort_by(&String.downcase(elem(&1, 0)), :asc)
  end

  defp list_users do
    Lightning.Accounts.list_users()
    |> Enum.map(fn user ->
      [
        key: "#{user.first_name} #{user.last_name} (#{user.email})",
        value: user.id
      ]
    end)
  end

  defp update_body(pid, id, body) do
    send_update(pid, __MODULE__, id: id, body: body)
  end

  defp save_credential(
         socket,
         :edit,
         credential_params
       ) do
    %{credential: form_credential} = socket.assigns

    with {:same_user, true} <-
           {:same_user,
            socket.assigns.current_user.id == socket.assigns.credential.user_id},
         {:ok, _credential} <-
           Credentials.update_credential(form_credential, credential_params) do
      socket =
        socket
        |> put_flash(:info, "Credential updated successfully")

      socket =
        if socket.assigns.return_to do
          push_navigate(socket, to: socket.assigns.return_to)
        else
          socket
        end

      {:noreply, socket}
    else
      {:same_user, false} ->
        socket =
          socket
          |> put_flash(
            :error,
            "Invalid credentials. Please log in again."
          )

        socket =
          if socket.assigns.return_to do
            push_navigate(socket, to: socket.assigns.return_to)
          else
            socket
          end

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_credential(
         %{assigns: %{changeset: changeset, schema: schema_name}} =
           socket,
         :new,
         credential_params
       ) do
    user_id = Ecto.Changeset.fetch_field!(changeset, :user_id)

    credential_params
    |> Map.put("user_id", user_id)
    |> Map.put("schema", schema_name)
    |> Credentials.create_credential()
    |> case do
      {:ok, credential} ->
        {:noreply, Helpers.handle_save_response(socket, credential)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp assigns_for_action(socket, opts \\ []) do
    page = determine_page(socket)
    is_reset? = Keyword.get(opts, :reset, false)

    socket =
      if changed?(socket, :project) or changed?(socket, :action) or is_reset?,
        do: assign_oauth_clients_and_type_options(socket),
        else: socket

    socket
    |> assigns_for_credential()
    |> assign(
      page: page,
      selected_oauth_client: socket.assigns[:oauth_client]
    )
  end

  defp determine_page(socket) do
    cond do
      Map.has_key?(socket.assigns, :page) and socket.assigns.page != nil ->
        socket.assigns.page

      socket.assigns.action == :new and socket.assigns.credential.schema == nil ->
        :first

      true ->
        :second
    end
  end

  defp assign_oauth_clients_and_type_options(socket) do
    %{project: project, current_user: current_user, action: action} =
      socket.assigns

    oauth_clients =
      if project,
        do: OauthClients.list_clients(project),
        else: OauthClients.list_clients(current_user)

    type_options =
      if action == :new do
        {:ok, schemas_path} =
          Application.fetch_env(:lightning, :schemas_path)

        get_type_options(schemas_path)
        |> Enum.concat(
          Enum.map(oauth_clients, fn client ->
            {client.name, client.id, "/images/oauth-2.png", "oauth"}
          end)
        )
        |> Enum.sort_by(&String.downcase(elem(&1, 0)), :asc)
      else
        []
      end

    assign(socket, oauth_clients: oauth_clients, type_options: type_options)
  end

  defp format_schema_name("raw"), do: "Raw JSON"
  defp format_schema_name("oauth"), do: "OAuth"
  defp format_schema_name("http"), do: "HTTP"

  defp format_schema_name(schema) when is_binary(schema) do
    schema
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp get_credential_description("raw", _type),
    do: "Define custom credentials in JSON"

  defp get_credential_description("keychain", _type),
    do: "Dynamically select linked credentials at runtime"

  defp get_credential_description(_key, "oauth"),
    do: "Connect with standards-based authorization"

  defp assigns_for_credential(socket) do
    %{
      id: component_id,
      projects: projects,
      credential: credential,
      allow_credential_transfer: allow_credential_transfer
    } = socket.assigns

    changeset = Credentials.change_credential(credential)

    schema = credential.schema || false

    selected_projects =
      changeset
      |> Ecto.Changeset.get_assoc(:project_credentials, :struct)
      |> Lightning.Repo.preload(:project)
      |> Enum.map(fn poc -> poc.project end)

    workflows_using_credentials =
      changeset
      |> Ecto.Changeset.get_assoc(:project_credentials, :struct)
      |> Enum.map(& &1.id)
      |> Lightning.Workflows.project_workflows_using_credentials()

    available_projects =
      Helpers.filter_available_projects(
        projects,
        selected_projects
      )

    users =
      if allow_credential_transfer do
        list_users()
      else
        []
      end

    pid = self()

    update_body = fn body ->
      update_body(pid, component_id, body)
    end

    {credential_environments, credential_bodies, original_environment_names} =
      if credential.id do
        credential = Lightning.Repo.preload(credential, :credential_bodies)

        environments =
          if Enum.empty?(credential.credential_bodies) do
            [%{name: "main"}]
          else
            credential.credential_bodies
            |> Enum.map(&%{name: &1.name})
            |> sort_environments()
          end

        bodies =
          Map.new(credential.credential_bodies, fn cb ->
            {cb.name, cb.body || %{}}
          end)

        original_environment_names =
          Enum.map(environments, & &1.name)

        {environments, bodies, original_environment_names}
      else
        {[%{name: "main"}], %{"main" => %{}}, []}
      end

    primary_env_name = find_primary_environment(credential_environments)

    assign(socket,
      users: users,
      update_body: update_body,
      changeset: changeset,
      schema: schema,
      selected_project: nil,
      selected_projects: selected_projects,
      workflows_using_credentials: workflows_using_credentials,
      available_projects: available_projects,
      credential_environments: credential_environments,
      credential_bodies: credential_bodies,
      original_environment_names: original_environment_names,
      current_tab: primary_env_name,
      environment_name_error: nil
    )
  end

  defp find_primary_environment(environments) do
    primary_names = [
      "main",
      "production",
      "prod",
      "master",
      "principal",
      "primary",
      "default"
    ]

    env_names = Enum.map(environments, & &1.name)

    primary_name =
      Enum.find(primary_names, fn name ->
        name in env_names
      end)

    primary_name || List.first(environments).name
  end

  defp generate_untitled_name(existing_names) do
    if "untitled" in existing_names do
      find_next_untitled(existing_names)
    else
      "untitled"
    end
  end

  defp find_next_untitled(existing_names, count \\ 1) do
    name = "untitled-#{count}"

    if name in existing_names do
      find_next_untitled(existing_names, count + 1)
    else
      name
    end
  end

  defp sort_environments(environments) do
    primary_names = [
      "main",
      "production",
      "prod",
      "master",
      "principal",
      "primary",
      "default"
    ]

    Enum.sort_by(environments, fn env ->
      case Enum.find_index(primary_names, &(&1 == env.name)) do
        nil -> {1, env.name}
        index -> {0, index}
      end
    end)
  end

  defp maybe_put_oauth_client_id(params, nil), do: params

  defp maybe_put_oauth_client_id(params, oauth_client) do
    Map.put(params, "oauth_client_id", oauth_client.id)
  end
end
