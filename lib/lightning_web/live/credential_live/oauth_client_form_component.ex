defmodule LightningWeb.CredentialLive.OauthClientFormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]

  alias Lightning.OauthClients
  alias LightningWeb.Components.NewInputs
  alias Phoenix.LiveView.JS

  @valid_assigns [
    :id,
    :action,
    :oauth_client,
    :allow_global,
    :projects,
    :button,
    :can_create_oauth_client,
    :return_to
  ]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, available_projects: [])}
  end

  @impl true
  def update(%{projects: projects} = assigns, socket) do
    changeset = OauthClients.change_client(assigns.oauth_client)
    all_projects = Enum.map(projects, &{&1.name, &1.id})
    initial_assigns = Map.filter(assigns, fn {k, _} -> k in @valid_assigns end)

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign_scopes(assigns.oauth_client, :mandatory_scopes)
     |> assign_scopes(assigns.oauth_client, :optional_scopes)
     |> assign_initial_values(changeset, all_projects)
     |> update_available_projects()}
  end

  defp assign_scopes(socket, oauth_client, scope_type) do
    scopes = Map.get(oauth_client, scope_type) |> to_string()
    scopes_list = String.split(scopes, ",", trim: true)

    updated_socket = assign(socket, scope_type, scopes_list)

    if scopes != "" do
      push_event(updated_socket, "clear_input", %{})
    else
      updated_socket
    end
  end

  defp assign_initial_values(socket, changeset, all_projects) do
    socket
    |> assign(:changeset, changeset)
    |> assign(:all_projects, all_projects)
    |> assign(:selected_project, nil)
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "_target" => ["oauth_client", "mandatory_scopes"],
          "oauth_client" => params
        },
        socket
      ) do
    value = Map.get(params, "mandatory_scopes")

    {:noreply, parse_and_update_scopes(socket, value, :mandatory_scopes)}
  end

  def handle_event(
        "validate",
        %{
          "_target" => ["oauth_client", "optional_scopes"],
          "oauth_client" => params
        },
        socket
      ) do
    value = Map.get(params, "optional_scopes")

    {:noreply, parse_and_update_scopes(socket, value, :optional_scopes)}
  end

  def handle_event("validate", %{"oauth_client" => oauth_client_params}, socket) do
    changeset =
      OauthClients.change_client(
        socket.assigns.oauth_client,
        oauth_client_params
      )
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("remove_mandatory_scope", %{"scope" => scope_value}, socket) do
    {:noreply, update_scopes(socket, :mandatory_scopes, scope_value, :remove)}
  end

  def handle_event("remove_optional_scope", %{"scope" => scope_value}, socket) do
    {:noreply, update_scopes(socket, :optional_scopes, scope_value, :remove)}
  end

  def handle_event("edit_mandatory_scope", %{"scope" => scope_value}, socket) do
    {:noreply, update_scopes(socket, :mandatory_scopes, scope_value, :edit)}
  end

  def handle_event("edit_optional_scope", %{"scope" => scope_value}, socket) do
    {:noreply, update_scopes(socket, :optional_scopes, scope_value, :edit)}
  end

  def handle_event(
        "select_item",
        %{"selected_project" => %{"id" => project_id}},
        socket
      ) do
    {:noreply, assign(socket, selected_project: project_id)}
  end

  def handle_event("add_new_project", %{"projectid" => project_id}, socket) do
    project_oauth_clients =
      fetch_field!(socket.assigns.changeset, :project_oauth_clients)

    project_oauth_clients =
      project_oauth_clients
      |> Enum.find(fn poc ->
        poc.project_id == project_id
      end)
      |> if do
        project_oauth_clients
        |> Enum.map(fn poc ->
          if poc.project_id == project_id do
            Ecto.Changeset.change(poc, %{delete: false})
          else
            poc
          end
        end)
      else
        Enum.concat(project_oauth_clients, [
          %Lightning.Projects.ProjectOauthClient{project_id: project_id}
        ])
      end

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_oauth_clients, project_oauth_clients)
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
    project_oauth_clients =
      fetch_field!(socket.assigns.changeset, :project_oauth_clients)

    project_oauth_clients =
      Enum.reduce(project_oauth_clients, [], fn poc, project_oauth_clients ->
        if poc.project_id == project_id do
          if is_nil(poc.id) do
            project_oauth_clients
          else
            project_oauth_clients ++
              [Ecto.Changeset.change(poc, %{delete: true})]
          end
        else
          project_oauth_clients ++ [poc]
        end
      end)

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_oauth_clients, project_oauth_clients)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(changeset: changeset, available_projects: available_projects)}
  end

  def handle_event("save", %{"oauth_client" => oauth_client_params}, socket) do
    if socket.assigns.can_create_oauth_client do
      save_oauth_client(
        socket,
        socket.assigns.action,
        oauth_client_params
      )
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")
       |> push_redirect(to: socket.assigns.return_to)}
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
  end

  defp update_scopes(socket, scope_key, scope_value, action) do
    scopes = socket.assigns[scope_key]

    new_scopes =
      Enum.reject(scopes, fn scope ->
        scope == scope_value
      end)

    case action do
      :remove ->
        socket
        |> assign(scope_key, new_scopes)
        |> push_event("clear_input", %{})

      :edit ->
        new_changeset =
          socket.assigns.changeset
          |> Ecto.Changeset.put_change(scope_key, scope_value)
          |> Ecto.Changeset.put_change(
            if(scope_key == :mandatory_scopes,
              do: :optional_scopes,
              else: :mandatory_scopes
            ),
            nil
          )

        socket
        |> assign(scope_key, new_scopes)
        |> assign(changeset: new_changeset)
    end
  end

  defp parse_and_update_scopes(socket, value, scope_type) do
    separators = ~r/[, ]+/

    if String.match?(value, separators) do
      existing_scopes = Map.get(socket.assigns, scope_type, [])
      updated_scopes = parse_scopes(value) |> merge_scopes(existing_scopes)

      socket
      |> push_event("clear_input", %{})
      |> assign(scope_type, updated_scopes)
    else
      socket
    end
  end

  defp parse_scopes(value) do
    value
    |> String.split(~r/[, ]+/, trim: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
  end

  defp merge_scopes(new_scopes, existing_scopes) do
    (new_scopes ++ existing_scopes)
    |> Enum.uniq()
    |> Enum.sort()
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

  defp save_oauth_client(socket, mode, oauth_client_params) do
    case mode do
      :edit ->
        params = add_scopes_to_params(oauth_client_params, socket)
        update_oauth_client(socket, params)

      :new ->
        params =
          add_scopes_to_params(oauth_client_params, socket)
          |> add_new_client_specific_fields(socket)

        create_oauth_client(socket, params)
    end
  end

  defp add_scopes_to_params(params, socket) do
    params
    |> Map.put("optional_scopes", Enum.join(socket.assigns.optional_scopes, ","))
    |> Map.put(
      "mandatory_scopes",
      Enum.join(socket.assigns.mandatory_scopes, ",")
    )
  end

  defp add_new_client_specific_fields(params, socket) do
    user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)

    project_oauth_clients =
      Ecto.Changeset.fetch_field!(
        socket.assigns.changeset,
        :project_oauth_clients
      )
      |> Enum.map(fn %{project_id: project_id} ->
        %{"project_id" => project_id}
      end)

    params
    |> Map.put("user_id", user_id)
    |> Map.put("project_oauth_clients", project_oauth_clients)
  end

  defp update_oauth_client(socket, params) do
    OauthClients.update_client(socket.assigns.oauth_client, params)
    |> handle_oauth_client_response(
      socket,
      {:info, "Oauth client updated successfully"}
    )
  end

  defp create_oauth_client(socket, params) do
    OauthClients.create_client(params)
    |> handle_oauth_client_response(
      socket,
      {:info, "Oauth client created successfully"}
    )
  end

  defp handle_oauth_client_response(
         {:ok, _oauth_client},
         socket,
         {message_type, message_content} = _flash_message
       ) do
    {:noreply,
     socket
     |> put_flash(message_type, message_content)
     |> push_redirect(to: socket.assigns.return_to)}
  end

  defp handle_oauth_client_response(
         {:error, %Ecto.Changeset{} = changeset},
         socket,
         _flash_message
       ) do
    {:noreply, assign(socket, :changeset, changeset)}
  end

  defp filter_available_projects(changeset, all_projects) do
    existing_ids =
      fetch_field!(changeset, :project_oauth_clients)
      |> Enum.reject(fn poc -> poc.delete end)
      |> Enum.map(fn poc -> poc.oauth_client_id end)

    Enum.reject(all_projects, fn {_, oauth_client_id} ->
      oauth_client_id in existing_ids
    end)
  end

  attr :projects, :list, required: true
  attr :selected, :map, required: true
  attr :allow_global, :boolean, default: false
  attr :phx_target, :any, default: nil
  attr :form, :map, required: true

  defp project_oauth_clients(assigns) do
    ~H"""
    <div class="col-span-3">
      <%= Phoenix.HTML.Form.label(@form, :project_oauth_clients, "Project Access",
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
            id={"project_oauth_clients_list_for_#{@form[:id].value}"}
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

      <div :if={@allow_global} class="rounded-md bg-yellow-200 p-4 mb-4">
        <h3 class="text-sm font-medium text-yellow-800">
          <LightningWeb.Components.Form.check_box
            form={@form}
            field={:global}
            label="Make client global (allow any user in this instance to use this client)"
          />
        </h3>
      </div>

      <div class="overflow-auto max-h-32">
        <.inputs_for
          :let={project_oauth_client}
          field={@form[:project_oauth_clients]}
        >
          <%= if project_oauth_client[:delete].value != true do %>
            <div class="flex w-full gap-2 items-center pb-2">
              <div class="grow">
                <%= project_name(@projects, project_oauth_client[:project_id].value) %>
                <.old_error field={project_oauth_client[:project_id]} />
              </div>
              <div class="grow-0 items-right">
                <.button
                  id={"delete-project-oauth-client-#{@form[:id].value}-button"}
                  phx-target={@phx_target}
                  phx-value-projectid={project_oauth_client[:project_id].value}
                  phx-click="delete_project"
                >
                  Remove
                </.button>
              </div>
            </div>
          <% end %>
          <.input type="hidden" field={project_oauth_client[:project_id]} />
          <.input
            type="hidden"
            field={project_oauth_client[:delete]}
            value={to_string(project_oauth_client[:delete].value)}
          />
        </.inputs_for>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :scopes, :list, required: true
  attr :label, :string, required: true
  attr :field, :any, required: true
  attr :on_delete, :string, required: true
  attr :on_edit, :string, required: true
  attr :phx_target, :any, required: true

  defp scopes_input(assigns) do
    ~H"""
    <div id={"generic-oauth-scopes-#{@id}"} class="space-y-2 mt-5">
      <NewInputs.label><%= @label %></NewInputs.label>
      <div class="flex flex-wrap items-center border border-gray-300 rounded-lg px-2">
        <span
          :for={scope <- @scopes}
          id={"#{@id}-#{scope}"}
          phx-hook={@on_edit}
          data-scope={scope}
          phx-target={@phx_target}
          class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1"
        >
          <%= scope %>
          <button
            type="button"
            phx-click={@on_delete}
            phx-value-scope={scope}
            phx-target={@phx_target}
            class="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
          >
            <span class="sr-only">Remove</span>
            <svg
              viewBox="0 0 14 14"
              class="h-3.5 w-3.5 stroke-gray-600/50 group-hover:stroke-gray-600/75"
            >
              <path d="M4 4l6 6m0-6l-6 6" />
            </svg>
            <span class="absolute -inset-1"></span>
          </button>
        </span>
        <NewInputs.input
          type="text"
          field={@field}
          phx-hook="ClearInput"
          class="flex-1 border-0 outline-0 ring-0 focus:border-0 focus:ring-0 focus:outline-0 focus:outline-transparent"
        />
      </div>
    </div>
    """
  end

  defp modal_title(assigns) do
    ~H"""
    <%= if @action in [:edit] do %>
      Edit Oauth Client
    <% else %>
      Add an Oauth Client
    <% end %>
    """
  end

  defp project_name(projects, id) do
    Enum.find_value(projects, fn {name, project_id} ->
      if project_id == id, do: name
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-10 sm:mt-0">
      <.modal id={@id} width="w-[64rem] sm:w-[32rem] md:w-[64rem]">
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
          id={"oauth-client-form-#{@oauth_client.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="space-y-6 bg-white px-4 px-6 sm:px-6">
            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:name]}
                  label="Name"
                  required="true"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:authorization_endpoint]}
                  label="Authorization URL"
                  required="true"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:token_endpoint]}
                  label="Token URL"
                  required="true"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:userinfo_endpoint]}
                  label="UserInfo URL"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="password"
                  field={f[:client_id]}
                  label="Client ID"
                  required="true"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="password"
                  field={f[:client_secret]}
                  label="Client Secret"
                  required="true"
                />
              </div>
            </div>

            <fieldset>
              <legend class="contents text-base font-medium text-gray-900">
                Manage Scopes
              </legend>
              <p class="text-sm text-gray-500">
                Type the names of the scopes and separate them using comma
              </p>
              <.scopes_input
                id={"mandatory-scopes-#{@oauth_client.id || "new"}"}
                field={f[:mandatory_scopes]}
                label="Mandatory Scopes"
                on_delete="remove_mandatory_scope"
                on_edit="EditMandatoryScope"
                scopes={@mandatory_scopes}
                phx_target={@myself}
              />

              <.scopes_input
                id={"optional-scopes-#{@oauth_client.id || "new"}"}
                field={f[:optional_scopes]}
                label="Optional Scopes"
                on_delete="remove_optional_scope"
                on_edit="EditOptionalScope"
                scopes={@optional_scopes}
                phx_target={@myself}
              />

              <div class="mt-5">
                <NewInputs.input
                  type="text"
                  field={f[:scopes_doc_url]}
                  label="Scopes Documentation URL"
                />
              </div>
            </fieldset>

            <div class="space-y-4">
              <fieldset>
                <legend class="contents text-base font-medium text-gray-900">
                  Project Access
                </legend>
                <p class="text-sm text-gray-500">
                  Control which projects have access to this credentials
                </p>
                <div class="mt-4">
                  <.project_oauth_clients
                    form={f}
                    projects={@all_projects}
                    selected={@selected_project}
                    allow_global={@allow_global}
                    phx_target={@myself}
                  />
                </div>
              </fieldset>
            </div>
          </div>
          <.modal_footer class="mt-6 mx-6">
            <div class="sm:flex sm:flex-row-reverse">
              <button
                type="submit"
                disabled={!@changeset.valid?}
                class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
              >
                <%= case @action do %>
                  <% :edit -> %>
                    Save Changes
                  <% :new -> %>
                    Add Oauth Client
                <% end %>
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
end
