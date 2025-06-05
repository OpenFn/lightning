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

  alias Phoenix.LiveView.JS

  @impl true
  def mount(%{assigns: init_assigns} = socket) do
    allow_credential_transfer =
      Application.fetch_env!(:lightning, LightningWeb)
      |> Keyword.get(:allow_credential_transfer)

    mount_assigns = %{
      on_save: nil,
      scopes: [],
      scopes_changed: false,
      sandbox_changed: false,
      schema: false,
      project: nil,
      available_projects: [],
      selected_projects: [],
      oauth_clients: [],
      allow_credential_transfer: allow_credential_transfer
    }

    {:ok,
     socket
     |> assign(mount_assigns)
     |> assign(init_assigns: init_assigns)
     |> assign(mount_assigns: mount_assigns)}
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

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assigns_for_action()
     |> assign_new(:component_assigns, fn -> assigns end)}
  end

  @impl true
  def handle_event("validate", %{"credential" => credential_params}, socket) do
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

  def handle_event("schema_selected", %{"selected" => type} = params, socket) do
    schema_selection_form = to_form(params)

    client =
      Enum.find(socket.assigns.oauth_clients, nil, fn client ->
        client.id == type
      end)

    schema = if client, do: "oauth", else: type

    changeset =
      Credentials.change_credential(socket.assigns.credential, %{schema: schema})

    {:noreply,
     socket
     |> assign(
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
    credential_params =
      maybe_add_oauth_specific_fields(socket, credential_params)

    if socket.assigns.can_create_project_credential do
      project_credentials =
        Helpers.prepare_projects_associations(
          socket.assigns.changeset,
          socket.assigns.selected_projects,
          :project_credentials
        )

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
       |> push_navigate(to: socket.assigns.return_to)}
    end
  end

  def handle_event("reset_state", _, socket) do
    reset_assigns =
      Map.take(socket.assigns, [
        :init_assigns,
        :mount_assigns,
        :component_assigns
      ])

    assigns =
      reset_assigns.init_assigns
      |> Map.merge(reset_assigns.mount_assigns)
      |> Map.merge(reset_assigns.component_assigns)

    socket =
      %{socket | assigns: assigns}
      |> assign(reset_assigns)
      |> assigns_for_action(reset: true)

    {:noreply, socket}
  end

  @impl true
  def render(%{page: :first} = assigns) do
    assigns =
      assigns
      |> assign_new(:schema_selection_form, fn ->
        to_form(%{"selected" => nil})
      end)

    ~H"""
    <div class="text-xs text-left">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
              id="close-credential-modal-type-picker"
              phx-click={hide_modal(@id) |> JS.push("reset_state", target: @myself)}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <div class="container mx-auto px-4">
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
        <:footer>
          <div class="sm:flex sm:flex-row-reverse gap-3">
            <.button
              type="submit"
              theme="primary"
              disabled={!@schema}
              phx-click="change_page"
              phx-target={@myself}
            >
              Configure credential
            </.button>
            <.button
              id="cancel-credential-type-picker"
              type="button"
              phx-click={hide_modal(@id) |> JS.push("reset_state", target: @myself)}
              theme="secondary"
            >
              Cancel
            </.button>
          </div>
        </:footer>
      </.modal>
    </div>
    """
  end

  def render(%{page: :second, schema: "oauth"} = assigns) do
    ~H"""
    <div class="text-left mt-10 sm:mt-0">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 w-[300px]">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
              id={"close-credential-modal-form-#{@credential.id || "new"}"}
              phx-click={hide_modal(@id) |> JS.push("reset_state", target: @myself)}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
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
          on_save={@on_save}
          allow_credential_transfer={@allow_credential_transfer}
          return_to={@return_to}
        />
      </.modal>
    </div>
    """
  end

  def render(%{page: :second} = assigns) do
    ~H"""
    <div class="text-left mt-10 sm:mt-0">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 w-[300px]">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
              id={"close-credential-modal-form-#{@credential.id || "new"}"}
              phx-click={hide_modal(@id) |> JS.push("reset_state", target: @myself)}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
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
                {fieldset}
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
                    <LightningWeb.Components.Credentials.projects_picker
                      id={@credential.id || "new"}
                      type={:credential}
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
        </.form>
        <:footer>
          <div class="sm:flex sm:flex-row-reverse gap-3">
            <.button
              id={"save-credential-button-#{@credential.id || "new"}"}
              type="submit"
              theme="primary"
              disabled={!@changeset.valid? or @scopes_changed or @sandbox_changed}
              form={"credential-form-#{@credential.id || "new"}"}
            >
              Save
            </.button>
            <.button
              type="button"
              phx-click={
                hide_modal(@id) |> JS.push("reset_state", target: @myself)
              }
              theme="secondary"
            >
              Cancel
            </.button>
          </div>
        </:footer>
      </.modal>
    </div>
    """
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
    |> Enum.concat([{"Raw JSON", "raw", nil, nil}])
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
       |> push_navigate(to: socket.assigns.return_to)}
    else
      {:same_user, false} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Invalid credentials. Please log in again."
         )
         |> push_navigate(to: socket.assigns.return_to)}

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
    page = if socket.assigns.action == :new, do: :first, else: :second

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

  defp assigns_for_credential(socket) do
    %{
      id: component_id,
      projects: projects,
      credential: credential,
      allow_credential_transfer: allow_credential_transfer
    } = socket.assigns

    scopes = get_scopes(credential)

    sandbox_value = get_sandbox_value(credential)

    api_version = get_api_version(credential)

    changeset = Credentials.change_credential(credential)

    schema = credential.schema || false

    selected_projects =
      changeset
      |> Ecto.Changeset.get_assoc(:project_credentials, :struct)
      |> Lightning.Repo.preload(:project)
      |> Enum.map(fn poc -> poc.project end)

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

    assign(socket,
      users: users,
      update_body: update_body,
      scopes: scopes,
      sandbox_value: sandbox_value,
      api_version: api_version,
      changeset: changeset,
      schema: schema,
      selected_project: nil,
      selected_projects: selected_projects,
      available_projects: available_projects
    )
  end
end
