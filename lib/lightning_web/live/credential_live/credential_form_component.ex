defmodule LightningWeb.CredentialLive.CredentialFormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.Credentials
  alias LightningWeb.Components.NewInputs
  alias LightningWeb.CredentialLive.GenericOauthComponent
  alias Phoenix.LiveView.JS

  @valid_assigns [
    :id,
    :action,
    :credential,
    :current_user,
    :projects,
    :on_save,
    :button,
    :can_create_project_credential,
    :oauth_clients,
    :return_to
  ]

  @impl true
  def mount(socket) do
    allow_credential_transfer =
      Application.fetch_env!(:lightning, LightningWeb)
      |> Keyword.get(:allow_credential_transfer)

<<<<<<< HEAD
    updated_socket =
      socket
      |> assign(scopes: [])
      |> assign(scopes_changed: false)
      |> assign(sandbox_changed: false)
      |> assign(schema: false)
      |> assign(available_projects: [])
      |> assign(selected_projects: [])
      |> assign(oauth_clients: [])
      |> assign(allow_credential_transfer: allow_credential_transfer)

=======
>>>>>>> 4286083d0 (Tweaks)
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    type_options = get_type_options(schemas_path)

    {:ok,
     socket
     |> assign(
       scopes: [],
       scopes_changed: false,
       schema: false,
       available_projects: [],
       selected_projects: [],
       oauth_clients: [],
       allow_credential_transfer: allow_credential_transfer,
       type_options: type_options
     )}
  end

  @impl true
  def update(%{body: body}, socket) do
    {:ok,
     update(socket, :changeset, fn changeset, %{credential: credential} ->
       params = changeset.params |> Map.put("body", body)
       Credentials.change_credential(credential, params)
     end)
     |> assign(scopes_changed: false)
     |> assign(sandbox_changed: false)}
  end

  def update(%{projects: projects} = assigns, socket) do
    pid = self()

    users = list_users()
    scopes = get_scopes(assigns.credential)

    sandbox_value = get_sandbox_value(assigns.credential)

    api_version = get_api_version(assigns.credential)

    changeset = Credentials.change_credential(assigns.credential)

    initial_assigns =
      Map.filter(assigns, &match?({k, _} when k in @valid_assigns, &1))

    update_body = fn body ->
      update_body(pid, assigns.id, body)
    end

    page = if assigns.action === :new, do: :first, else: :second

    schema = assigns.credential.schema || false

    type_options =
      if assigns.action === :new,
        do:
          socket.assigns.type_options ++
            Enum.map(assigns.oauth_clients, fn client ->
              {client.name, client.id, nil, "oauth"}
            end),
        else: []

    type_options = Enum.sort_by(type_options, & &1, :asc)

    selected_projects =
      changeset
      |> Ecto.Changeset.get_assoc(:project_credentials, :struct)
      |> Lightning.Repo.preload(:project)
      |> Enum.map(fn poc -> poc.project end)

    available_projects =
      filter_available_projects(projects, selected_projects)

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign(page: page)
     |> assign(users: users)
     |> assign(scopes: scopes)
     |> assign(sandbox_value: sandbox_value)
     |> assign(api_version: api_version)
     |> assign(changeset: changeset)
     |> assign(update_body: update_body)
     |> assign(projects: projects)
     |> assign(selected_oauth_client: assigns.credential.oauth_client)
     |> assign(schema: schema)
     |> assign(selected_project: nil)
     |> assign(selected_projects: selected_projects)
     |> assign(available_projects: available_projects)
     |> assign(type_options: type_options)}
  end

  @impl true
  def handle_event("validate", %{"credential" => credential_params}, socket) do
    IO.inspect("ARE YOU CALLED FROM CREDENTIAL FORM?")

    changeset =
      Credentials.change_credential(
        socket.assigns.credential,
        credential_params |> Map.put("schema", socket.assigns.schema)
      )
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(
        socket.assigns.projects,
        socket.assigns.selected_projects
      )

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> assign(:available_projects, available_projects)
     |> assign(selected_project: nil)}
  end

  def handle_event("scopes_changed", %{"_target" => [scope]}, socket) do
    selected_scopes =
      if Enum.member?(socket.assigns.scopes, scope) do
        Enum.reject(socket.assigns.scopes, fn value -> value == scope end)
      else
        [scope | socket.assigns.scopes]
      end

    send_update(LightningWeb.CredentialLive.OauthComponent,
      id: "inner-form-#{socket.assigns.credential.id || "new"}",
      scopes: selected_scopes
    )

    saved_scopes = get_scopes(socket.assigns.credential)
    diff_scopes = Enum.sort(selected_scopes) == Enum.sort(saved_scopes)

    {:noreply,
     socket
     |> assign(scopes: selected_scopes)
     |> assign(scopes_changed: !diff_scopes)}
  end

  def handle_event("check_sandbox", %{"sandbox" => value}, socket) do
    sandbox_value = String.to_existing_atom(value)

    send_update(LightningWeb.CredentialLive.OauthComponent,
      id: "inner-form-#{socket.assigns.credential.id || "new"}",
      sandbox: sandbox_value
    )

    {:noreply,
     assign(socket, sandbox_value: sandbox_value, sandbox_changed: true)}
  end

  def handle_event("api_version", %{"api_version" => version}, socket) do
    {:noreply, assign(socket, api_version: version)}
  end

  def handle_event(
        "schema_selected",
        %{"selected" => type} = _params,
        socket
      ) do
    client =
      Enum.find(socket.assigns.oauth_clients, nil, fn client ->
        client.id == type
      end)

    schema = if client, do: "oauth", else: type

    changeset =
      Credentials.change_credential(socket.assigns.credential, %{schema: schema})

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> assign(schema: schema)
     |> assign(selected_oauth_client: client)}
  end

  def handle_event(
        "schema_selected",
        %{"_target" => ["selected"]},
        socket
      ) do
    {:noreply, socket}
  end

  def handle_event("change_page", _, socket) do
    {:noreply, socket |> assign(page: :second)}
  end

  def handle_event(
        "select_item",
        %{"project_id" => project_id},
        socket
      ) do
    {:noreply, socket |> assign(selected_project: project_id)}
  end

  def handle_event("add_new_project", %{"project_id" => project_id}, socket) do
    selected =
      socket.assigns.available_projects
      |> Enum.find(fn project -> project_id == project.id end)

    selected_projects = socket.assigns.selected_projects ++ [selected]

    available_projects =
      filter_available_projects(socket.assigns.projects, selected_projects)

    {:noreply,
     socket
     |> assign(
       available_projects: available_projects,
       selected_projects: selected_projects,
       selected_project: nil
     )}
  end

  def handle_event("delete_project", %{"project_id" => project_id}, socket) do
    selected =
      socket.assigns.selected_projects
      |> Enum.find(fn project -> project_id == project.id end)

    selected_projects =
      socket.assigns.selected_projects
      |> Enum.reject(fn project -> project.id == selected.id end)

    available_projects =
      filter_available_projects(socket.assigns.projects, selected_projects)

    {:noreply,
     socket
     |> assign(
       available_projects: available_projects,
       selected_projects: selected_projects
     )}
  end

  def handle_event("save", %{"credential" => credential_params}, socket) do
    credential_params =
      maybe_add_oauth_specific_fields(socket, credential_params)

    if socket.assigns.can_create_project_credential do
      project_credentials = prepare_projects(socket)

      credential_params =
        Map.put(credential_params, "project_credentials", project_credentials)

      save_credential(
        socket,
        socket.assigns.action,
        credential_params
      )
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")
       |> push_redirect(to: socket.assigns.return_to)}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply,
     socket
     |> push_navigate(to: socket.assigns.return_to)}
  end

  defp prepare_projects(socket) do
    project_credentials =
      Ecto.Changeset.fetch_field!(
        socket.assigns.changeset,
        :project_credentials
      )

    selected_projects_ids =
      Enum.map(socket.assigns.selected_projects, fn project -> project.id end)

    projects_to_delete =
      project_credentials
      |> Enum.filter(fn poc -> poc.project_id not in selected_projects_ids end)
      |> Enum.map(fn poc ->
        %{
          "id" => poc.id,
          "project_id" => poc.project_id,
          "delete" => "true"
        }
      end)

    projects_to_keep =
      project_credentials
      |> Enum.filter(fn poc -> poc.project_id in selected_projects_ids end)
      |> Enum.map(fn poc ->
        %{
          "id" => poc.id,
          "project_id" => poc.project_id
        }
      end)

    projects_to_add =
      selected_projects_ids
      |> Enum.reject(fn id ->
        id in Enum.map(project_credentials, & &1.project_id)
      end)
      |> Enum.map(fn id -> %{"project_id" => id} end)

    projects_to_delete ++ projects_to_add ++ projects_to_keep
  end

  @impl true
  def render(%{page: :first} = assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
              id="close-credential-modal-type-picker"
              phx-click="close_modal"
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <div class="container mx-auto px-4">
          <.form
            :let={f}
            id="credential-schema-picker"
            for={%{}}
            phx-target={@myself}
            phx-change="schema_selected"
          >
            <div class="grid grid-cols-2 md:grid-cols-4 sm:grid-cols-3 gap-4 overflow-auto max-h-99">
              <div
                :for={{name, key, logo, _id} <- @type_options}
                class="flex items-center p-2"
              >
                <%= Phoenix.HTML.Form.radio_button(f, :selected, key,
                  id: "credential-schema-picker_selected_#{key}",
                  class:
                    "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500"
                ) %>
                <LightningWeb.Components.Form.label_field
                  form={f}
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
        <.modal_footer class="mt-6 mx-6">
          <div class="sm:flex sm:flex-row-reverse">
            <button
              type="submit"
              disabled={!@schema}
              phx-click="change_page"
              phx-target={@myself}
              class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
            >
              Configure credential
            </button>
            <button
              id="cancel-credential-type-picker"
              type="button"
              phx-click="close_modal"
              phx-target={@myself}
              class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
            >
              Cancel
            </button>
          </div>
        </.modal_footer>
      </.modal>
    </div>
    """
  end

  def render(%{page: :second, schema: "oauth"} = assigns) do
    ~H"""
    <div class="mt-10 sm:mt-0">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 w-[300px]">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
              id={"close-credential-modal-form-#{@credential.id || "new"}"}
              phx-click="close_modal"
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <LightningWeb.Components.Oauth.missing_client_warning :if={
          !@selected_oauth_client
        } />
        <.live_component
          module={GenericOauthComponent}
          id={"generic-oauth-component-#{@credential.id || "new"}"}
          action={@action}
          selected_client={@selected_oauth_client}
          changeset={@changeset}
          credential={@credential}
          projects={@projects}
          users={@users}
          allow_credential_transfer={@allow_credential_transfer}
          return_to={@return_to}
        />
      </.modal>
    </div>
    """
  end

  def render(%{page: :second} = assigns) do
    ~H"""
    <div class="mt-10 sm:mt-0">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
              id={"close-credential-modal-form-#{@credential.id || "new"}"}
              phx-click="close_modal"
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <.form
          :let={f}
          for={@changeset}
          id={"credential-form-#{@credential.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <LightningWeb.Components.Credentials.form_component
            :let={{fieldset, _valid?}}
            id={@credential.id || "new"}
            schema={@schema}
            form={f}
            type={@schema}
            action={@action}
            update_body={@update_body}
            oauth_clients={@oauth_clients}
            scopes_changed={@scopes_changed}
            sandbox_changed={@sandbox_changed}
          >
            <div class="space-y-6 bg-white px-4 py-5 sm:p-6">
              <fieldset>
                <div class="space-y-4">
                  <div>
                    <NewInputs.input type="text" field={f[:name]} label="Name" />
                  </div>
                  <div>
                    <LightningWeb.Components.Form.check_box
                      form={f}
                      field={:production}
                    />
                  </div>
                </div>
              </fieldset>
              <div class="space-y-4">
                <div class="hidden sm:block" aria-hidden="true">
                  <div class="border-t border-secondary-200"></div>
                </div>
                <!-- # TODO: Make this part of the fieldset to avoid the if block -->
                <LightningWeb.CredentialLive.Scopes.scopes_picklist
                  :if={@schema in ["salesforce_oauth", "googlesheets"]}
                  id={"scope_selection_#{@credential.id || "new"}"}
                  target={@myself}
                  on_change="scopes_changed"
                  selected_scopes={@scopes}
                  schema={@schema}
                />
                <.input
                  :if={@schema in ["salesforce_oauth"]}
                  class="mb-2"
                  name="sandbox"
                  type="checkbox"
                  value={@sandbox_value}
                  label="Sandbox instance?"
                  phx-change="check_sandbox"
                  phx-target={@myself}
                  id={"salesforce_sandbox_instance_checkbox_#{@credential.id || "new"}"}
                />

                <.input
                  :if={@schema in ["salesforce_oauth"]}
                  type="text"
                  class="mb-2"
                  name="api_version"
                  label="API Version"
                  value={@api_version}
                  phx-change="api_version"
                  phx-target={@myself}
                  id={"salesforce_api_version_input_#{@credential.id || "new"}"}
                />
                <%= fieldset %>
              </div>

              <div class="space-y-4">
                <div class="hidden sm:block" aria-hidden="true">
                  <div class="border-t border-secondary-200 mb-6"></div>
                </div>
                <fieldset>
                  <legend class="contents text-base font-medium text-gray-900">
                    Project Access
                  </legend>
                  <p class="text-sm text-gray-500">
                    Control which projects have access to this credentials
                  </p>
                  <div class="mt-4">
                    <LightningWeb.Components.Credentials.project_credentials
                      available_projects={@available_projects}
                      selected_projects={@selected_projects}
                      projects={@projects}
                      selected={@selected_project}
                      phx_target={@myself}
                    />
                  </div>
                </fieldset>
              </div>
              <div
                :if={@action == :edit and @allow_credential_transfer}
                class="space-y-4"
              >
                <LightningWeb.Components.Credentials.credential_transfer
                  form={f}
                  users={@users}
                />
              </div>
            </div>
          </LightningWeb.Components.Credentials.form_component>
          <.modal_footer class="mt-6 mx-6">
            <div class="sm:flex sm:flex-row-reverse">
              <button
                id={
                  "save-credential-button-#{@credential.id || "new"}"
                }
                type="submit"
                disabled={!@changeset.valid? or @scopes_changed or @sandbox_changed}
                class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
              >
                Save
              </button>
              <button
                type="button"
                phx-click={JS.navigate(@return_to)}
                class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
              >
                Cancel
              </button>
            </div>
          </.modal_footer>
        </.form>
      </.modal>
    </div>
    """
  end

  defp update_available_projects(socket) do
    update(
      socket,
      :available_projects,
      fn _,
         %{
           all_projects: all_projects,
           changeset: changeset
         } ->
        filter_available_projects(changeset, all_projects)
      end
    )
  end

  defp maybe_add_oauth_specific_fields(socket, params) do
    if socket.assigns.schema in ["salesforce_oauth", "googlesheets"] do
      updated_body =
        params["body"]
        |> Map.put("sandbox", socket.assigns.sandbox_value)
        |> Map.put("apiVersion", socket.assigns.api_version)

      %{params | "body" => updated_body}
    else
      params
    end
  end

  defp get_type_options(schemas_path) do
    schemas_options =
      Path.wildcard("#{schemas_path}/*.json")
      |> Enum.map(fn p ->
        name = p |> Path.basename() |> String.replace(".json", "")
        {name |> Phoenix.HTML.Form.humanize(), name, nil, nil}
      end)

    oauth_clients_from_env =
      Application.get_env(:lightning, :oauth_clients)

    schemas_options
    |> Enum.concat([{"Raw JSON", "raw", nil, nil}])
    |> handle_oauth_item(
      {"GoogleSheets", "googlesheets", ~p"/images/oauth-2.png", nil},
      get_in(oauth_clients_from_env, [:google, :client_id])
    )
    |> handle_oauth_item(
      {
        "Salesforce",
        "salesforce_oauth",
        ~p"/images/oauth-2.png",
        nil
      },
      get_in(oauth_clients_from_env, [:salesforce, :client_id])
    )
    |> Enum.sort_by(& &1, :asc)
  end

  defp handle_oauth_item(list, {_label, id, _image, _} = item, client_id) do
    if is_nil(client_id) || Enum.member?(list, item) do
      # Replace
      Enum.reject(list, fn {_first, second, _third, _} -> second == id end)
    else
      Enum.map(list, fn
        {_old_label, old_id, _old_image, _} when old_id == id -> item
        old_item -> old_item
      end)
      |> append_if_missing(item)
    end
  end

  defp append_if_missing(list, item) do
    if Enum.member?(list, item), do: list, else: list ++ [item]
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

  defp get_scopes(%{body: %{"scope" => scope}}), do: String.split(scope)
  defp get_scopes(_), do: []

  defp get_sandbox_value(%{body: %{"sandbox" => sandbox}}) do
    if is_boolean(sandbox) do
      sandbox
    else
      String.to_atom(sandbox)
    end
  end

  defp get_sandbox_value(_), do: false

  defp get_api_version(%{body: %{"apiVersion" => api_version}}), do: api_version

  defp get_api_version(_), do: nil

  defp modal_title(assigns) do
    ~H"""
    <%= if @action in [:edit] do %>
      Edit a credential
    <% else %>
      Add a credential
    <% end %>
    """
  end

  # NOTE: this function is sometimes called from inside a Task and therefore
  # requires a `pid`
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
      {:noreply,
       socket
       |> put_flash(:info, "Credential updated successfully")
       |> push_redirect(to: socket.assigns.return_to)}
    else
      {:same_user, false} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Invalid credentials. Please log in again."
         )
         |> push_redirect(to: socket.assigns.return_to)}

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

    project_credentials =
      Ecto.Changeset.fetch_field!(changeset, :project_credentials)
      |> Enum.map(fn %{project_id: project_id} ->
        %{"project_id" => project_id}
      end)

    credential_params
    |> Map.put("user_id", user_id)
    |> Map.put("schema", schema_name)
    |> Map.put("project_credentials", project_credentials)
    |> Credentials.create_credential()
    |> case do
      {:ok, credential} ->
        if socket.assigns[:on_save] do
          socket.assigns[:on_save].(credential)
          {:noreply, push_event(socket, "close_modal", %{})}
        else
          {:noreply,
           socket
           |> put_flash(:info, "Credential created successfully")
           |> push_redirect(to: socket.assigns.return_to)}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp filter_available_projects(projects, selected_projects) do
    if selected_projects == [] do
      projects
    else
      existing_ids = Enum.map(selected_projects, fn project -> project.id end)

      Enum.reject(projects, fn %{id: project_id} ->
        project_id in existing_ids
      end)
    end
  end
end
