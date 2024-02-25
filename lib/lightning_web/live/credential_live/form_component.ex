defmodule LightningWeb.CredentialLive.FormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]

  alias Lightning.Credentials
  alias LightningWeb.Components.NewInputs
  alias LightningWeb.CredentialLive.JsonSchemaBodyComponent
  alias LightningWeb.CredentialLive.OauthComponent
  alias LightningWeb.CredentialLive.RawBodyComponent
  alias Phoenix.LiveView.JS

  @valid_assigns [
    :id,
    :action,
    :credential,
    :projects,
    :on_save,
    :button,
    :show_project_credentials,
    :can_create_project_credential,
    :return_to
  ]

  @impl true
  def mount(socket) do
    allow_credential_transfer =
      Application.fetch_env!(:lightning, LightningWeb)
      |> Keyword.get(:allow_credential_transfer)

    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    type_options = get_type_options(socket, schemas_path)

    {:ok,
     socket
     |> assign(scopes: [])
     |> assign(type_options: type_options)
     |> assign(scopes_changed: false)
     |> assign(authorization_status: :success)
     |> assign(schema: false)
     |> assign(available_projects: [])
     |> assign(allow_credential_transfer: allow_credential_transfer)}
  end

  @impl true
  def update(%{body: body}, socket) do
    {:ok,
     update(socket, :changeset, fn changeset, %{credential: credential} ->
       params = changeset.params |> Map.put("body", body)
       Credentials.change_credential(credential, params)
     end)
     |> assign(scopes_changed: false)}
  end

  def update(%{authorization_status: status}, socket) do
    {:ok, assign(socket, authorization_status: status)}
  end

  def update(%{projects: projects} = assigns, socket) do
    pid = self()

    users = list_users()
    scopes = get_scopes(assigns.credential)

    sandbox_value = get_sandbox_value(assigns.credential)

    changeset = Credentials.change_credential(assigns.credential)
    all_projects = Enum.map(projects, &{&1.name, &1.id})

    initial_assigns =
      Map.filter(assigns, &match?({k, _} when k in @valid_assigns, &1))

    update_body = fn body ->
      update_body(pid, assigns.id, body)
    end

    page = if assigns.action === :new, do: :first, else: :second

    schema = assigns.credential.schema || false

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign(page: page)
     |> assign(users: users)
     |> assign(scopes: scopes)
     |> assign(sandbox_value: sandbox_value)
     |> assign(changeset: changeset)
     |> assign(update_body: update_body)
     |> assign(all_projects: all_projects)
     |> assign(schema: schema)
     |> assign(selected_project: nil)
     |> assign_new(:show_project_credentials, fn -> true end)
     |> update_available_projects()}
  end

  @impl true
  def handle_event("validate", %{"credential" => credential_params}, socket) do
    changeset =
      Credentials.change_credential(
        socket.assigns.credential,
        credential_params |> Map.put("schema", socket.assigns.schema)
      )
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset)}
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
    sandbox_value = String.to_atom(value)

    send_update(LightningWeb.CredentialLive.OauthComponent,
      id: "inner-form-#{socket.assigns.credential.id || "new"}",
      sandbox: sandbox_value
    )

    {:noreply, socket |> assign(sandbox_value: sandbox_value)}
  end

  def handle_event(
        "schema_selected",
        %{"selected" => type} = _params,
        socket
      ) do
    changeset =
      Credentials.change_credential(socket.assigns.credential, %{schema: type})

    {:noreply,
     socket
     |> assign(changeset: changeset)
     |> assign(schema: type)}
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
        %{"selected_project" => %{"id" => project_id}},
        socket
      ) do
    {:noreply, socket |> assign(selected_project: project_id)}
  end

  def handle_event("add_new_project", %{"projectid" => project_id}, socket) do
    project_credentials =
      fetch_field!(socket.assigns.changeset, :project_credentials)

    project_credentials =
      if Enum.find(project_credentials, fn pu -> pu.project_id == project_id end) do
        Enum.map(project_credentials, fn pu ->
          if pu.project_id == project_id do
            Ecto.Changeset.change(pu, %{delete: false})
          else
            pu
          end
        end)
      else
        Enum.concat(project_credentials, [
          %Lightning.Projects.ProjectCredential{project_id: project_id}
        ])
      end

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_credentials, project_credentials)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(
       changeset: changeset,
       available_projects: available_projects,
       selected_project: nil
     )}
  end

  def handle_event("delete_project", %{"projectid" => project_id}, socket) do
    project_credentials =
      fetch_field!(socket.assigns.changeset, :project_credentials)

    project_credentials =
      Enum.reduce(project_credentials, [], fn pc, project_credentials ->
        if pc.project_id == project_id do
          if is_nil(pc.id) do
            project_credentials
          else
            project_credentials ++ [Ecto.Changeset.change(pc, %{delete: true})]
          end
        else
          project_credentials ++ [pc]
        end
      end)

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_credentials, project_credentials)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(changeset: changeset, available_projects: available_projects)}
  end

  def handle_event("save", %{"credential" => credential_params}, socket) do
    if socket.assigns.can_create_project_credential do
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

  @impl true
  def render(%{page: :first} = assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
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
                :for={{name, key, logo} <- @type_options}
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

  def render(%{page: :second} = assigns) do
    ~H"""
    <div class="mt-10 sm:mt-0">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
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
          <.form_component
            :let={{fieldset, _valid?}}
            id={@credential.id || "new"}
            schema={@schema}
            parent_id={@id}
            form={f}
            type={@schema}
            action={@action}
            sandbox_value={@sandbox_value}
            update_body={@update_body}
            scopes_changed={@scopes_changed}
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
                  type="checkbox"
                  name="sandbox"
                  value={@sandbox_value}
                  phx-change="check_sandbox"
                  label="Sandbox instance?"
                  class="mb-2"
                />
                <%= fieldset %>
              </div>

              <div :if={@show_project_credentials} class="space-y-4">
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
                    <.project_credentials
                      form={f}
                      projects={@all_projects}
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
                <.credential_transfer form={f} users={@users} />
              </div>
            </div>
          </.form_component>
          <.modal_footer class="mt-6 mx-6">
            <div class="sm:flex sm:flex-row-reverse">
              <button
                type="submit"
                disabled={
                  !@changeset.valid? or @scopes_changed or
                    @authorization_status !== :success
                }
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

  attr :id, :string, required: false
  attr :type, :string, required: true
  attr :form, :map, required: true
  attr :action, :any, required: false
  attr :phx_target, :any, default: nil
  attr :parent_id, :string, required: false
  attr :schema, :string, required: false
  attr :sandbox_value, :boolean, default: false
  attr :update_body, :any, required: false
  attr :scopes_changed, :boolean, required: false
  slot :inner_block

  defp form_component(%{type: "googlesheets"} = assigns) do
    ~H"""
    <OauthComponent.fieldset
      :let={l}
      id={@id}
      form={@form}
      action={@action}
      schema={@schema}
      parent_id={@parent_id}
      update_body={@update_body}
    >
      <%= render_slot(@inner_block, l) %>
    </OauthComponent.fieldset>
    """
  end

  defp form_component(%{type: "salesforce_oauth"} = assigns) do
    ~H"""
    <OauthComponent.fieldset
      :let={l}
      id={@id}
      form={@form}
      action={@action}
      schema={@schema}
      parent_id={@parent_id}
      update_body={@update_body}
      sandbox_value={@sandbox_value}
      scopes_changed={@scopes_changed}
    >
      <%= render_slot(@inner_block, l) %>
    </OauthComponent.fieldset>
    """
  end

  defp form_component(%{type: "raw"} = assigns) do
    ~H"""
    <RawBodyComponent.fieldset :let={l} form={@form}>
      <%= render_slot(@inner_block, l) %>
    </RawBodyComponent.fieldset>
    """
  end

  defp form_component(%{type: _schema} = assigns) do
    ~H"""
    <JsonSchemaBodyComponent.fieldset :let={l} form={@form}>
      <%= render_slot(@inner_block, l) %>
    </JsonSchemaBodyComponent.fieldset>
    """
  end

  attr :projects, :list, required: true
  attr :selected, :map, required: true
  attr :phx_target, :any, default: nil
  attr :form, :map, required: true

  defp project_credentials(assigns) do
    ~H"""
    <div class="col-span-3">
      <%= Phoenix.HTML.Form.label(@form, :project_credentials, "Project Access",
        class: "block text-sm font-medium text-secondary-700"
      ) %>

      <div class="flex w-full items-center gap-2 pb-3 mt-1">
        <div class="grow">
          <LightningWeb.Components.Form.select_field
            form={:selected_project}
            name={:id}
            values={@projects}
            value={@selected}
            prompt=""
            phx-change="select_item"
            phx-target={@phx_target}
            id={"project_list_for_#{@form[:id].value}"}
          />
        </div>
        <div class="grow-0 items-right">
          <.button
            id={"add-new-project-button-to-#{@form[:id].value}"}
            disabled={@selected == ""}
            phx-target={@phx_target}
            phx-value-projectid={@selected}
            phx-click="add_new_project"
          >
            Add
          </.button>
        </div>
      </div>

      <.inputs_for :let={project_credential} field={@form[:project_credentials]}>
        <%= if project_credential[:delete].value != true do %>
          <div class="flex w-full gap-2 items-center pb-2">
            <div class="grow">
              <%= project_name(@projects, project_credential[:project_id].value) %>
              <.old_error field={project_credential[:project_id]} />
            </div>
            <div class="grow-0 items-right">
              <.button
                phx-target={@phx_target}
                phx-value-projectid={project_credential[:project_id].value}
                phx-click="delete_project"
              >
                Remove
              </.button>
            </div>
          </div>
        <% end %>
        <.input type="hidden" field={project_credential[:project_id]} />
        <.input
          type="hidden"
          field={project_credential[:delete]}
          value={to_string(project_credential[:delete].value)}
        />
      </.inputs_for>
    </div>
    """
  end

  attr :users, :list, required: true
  attr :form, :map, required: true

  defp credential_transfer(assigns) do
    ~H"""
    <div class="hidden sm:block" aria-hidden="true">
      <div class="border-t border-secondary-200 mb-6"></div>
    </div>
    <fieldset>
      <legend class="contents text-base font-medium text-gray-900">
        Transfer Ownership
      </legend>
      <p class="text-sm text-gray-500">
        Assign ownership of this credential to someone else.
      </p>
      <div class="mt-4">
        <%= Phoenix.HTML.Form.label(@form, :owner,
          class: "block text-sm font-medium text-secondary-700"
        ) %>
        <LightningWeb.Components.Form.select_field
          form={@form}
          name={:user_id}
          values={@users}
        />
        <.old_error field={@form[:user_id]} />
      </div>
    </fieldset>
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

  defp get_type_options(socket, schemas_path) do
    schemas_options =
      Path.wildcard("#{schemas_path}/*.json")
      |> Enum.map(fn p ->
        name = p |> Path.basename() |> String.replace(".json", "")
        {name |> Phoenix.HTML.Form.humanize(), name, nil}
      end)

    oauth_clients =
      Application.get_env(:lightning, :oauth_clients)

    schemas_options
    |> Enum.concat([{"Raw JSON", "raw", nil}])
    |> handle_oauth_item(
      {"GoogleSheets", "googlesheets",
       Routes.static_path(socket, "/images/oauth-2.png")},
      get_in(oauth_clients, [:google, :client_id])
    )
    |> handle_oauth_item(
      {
        "Salesforce",
        "salesforce_oauth",
        Routes.static_path(socket, "/images/oauth-2.png")
      },
      get_in(oauth_clients, [:salesforce, :client_id])
    )
    |> Enum.sort_by(& &1, :asc)
  end

  defp handle_oauth_item(list, {_label, id, _image} = item, client_id) do
    if is_nil(client_id) || Enum.member?(list, item) do
      # Replace
      Enum.reject(list, fn {_first, second, _third} -> second == id end)
    else
      Enum.map(list, fn
        {_old_label, old_id, _old_image} when old_id == id -> item
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

  defp project_name(projects, id) do
    Enum.find_value(projects, fn {name, project_id} ->
      if project_id == id, do: name
    end)
  end

  defp save_credential(socket, :edit, credential_params) do
    case Credentials.update_credential(
           socket.assigns.credential,
           credential_params
         ) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential updated successfully")
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

  defp filter_available_projects(changeset, all_projects) do
    existing_ids =
      fetch_field!(changeset, :project_credentials)
      |> Enum.reject(fn pu -> pu.delete end)
      |> Enum.map(fn pu -> pu.credential_id end)

    all_projects
    |> Enum.reject(fn {_, credential_id} -> credential_id in existing_ids end)
  end
end
