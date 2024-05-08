defmodule LightningWeb.CredentialLive.OauthClientFormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

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
    {:ok,
     assign(socket,
       available_projects: [],
       selected_projects: [],
       is_global: false
     )}
  end

  @impl true
  def update(%{projects: projects} = assigns, socket) do
    changeset = OauthClients.change_client(assigns.oauth_client)
    initial_assigns = Map.filter(assigns, fn {k, _} -> k in @valid_assigns end)

    selected_projects =
      changeset
      |> Ecto.Changeset.get_assoc(:project_oauth_clients, :struct)
      |> Lightning.Repo.preload(:project)
      |> Enum.map(fn poc -> poc.project end)

    available_projects =
      filter_available_projects(projects, selected_projects)

    is_global = Ecto.Changeset.fetch_field!(changeset, :global)

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign_scopes(assigns.oauth_client, :mandatory_scopes)
     |> assign_scopes(assigns.oauth_client, :optional_scopes)
     |> assign(:changeset, changeset)
     |> assign(:projects, projects)
     |> assign(:selected_project, nil)
     |> assign(:available_projects, available_projects)
     |> assign(:selected_projects, selected_projects)
     |> assign(:is_global, is_global)}
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

    updated_socket =
      socket |> assign(:changeset, changeset) |> maybe_clear_selected_projects()

    available_projects =
      filter_available_projects(
        updated_socket.assigns.projects,
        updated_socket.assigns.selected_projects
      )

    is_global = Ecto.Changeset.fetch_field!(changeset, :global)

    {:noreply,
     assign(updated_socket,
       is_global: is_global,
       available_projects: available_projects,
       selected_project: nil
     )}
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
        %{"project_id" => project_id},
        socket
      ) do
    {:noreply,
     socket
     |> assign(selected_project: project_id)
     |> push_event("clear_input", %{})}
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
     )
     |> push_event("clear_input", %{})}
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
     )
     |> push_event("clear_input", %{})}
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

  defp maybe_clear_selected_projects(socket) do
    if Ecto.Changeset.changed?(socket.assigns.changeset, :global) and
         !Ecto.Changeset.get_change(socket.assigns.changeset, :global) do
      assign(socket, selected_projects: [])
    else
      socket
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

  defp save_oauth_client(socket, mode, oauth_client_params) do
    project_oauth_clients =
      Ecto.Changeset.fetch_field!(
        socket.assigns.changeset,
        :project_oauth_clients
      )

    selected_projects_ids =
      Enum.map(socket.assigns.selected_projects, fn project -> project.id end)

    projects_to_delete =
      project_oauth_clients
      |> Enum.filter(fn poc -> poc.project_id not in selected_projects_ids end)
      |> Enum.map(fn poc ->
        %{
          "id" => poc.id,
          "project_id" => poc.project_id,
          "delete" => "true"
        }
      end)

    projects_to_keep =
      project_oauth_clients
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
        id in Enum.map(project_oauth_clients, & &1.project_id)
      end)
      |> Enum.map(fn id -> %{"project_id" => id} end)

    project_oauth_clients =
      projects_to_delete ++ projects_to_add ++ projects_to_keep

    case mode do
      :edit ->
        params =
          add_scopes_to_params(oauth_client_params, socket)
          |> Map.put("project_oauth_clients", project_oauth_clients)

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

  attr :available_projects, :list, required: true
  attr :projects, :list, required: true
  attr :selected_projects, :list, required: true
  attr :selected, :string, required: true
  attr :allow_global, :boolean, default: false
  attr :global, :boolean, required: true
  attr :phx_target, :any, default: nil
  attr :form, :any, required: true

  defp project_oauth_clients(assigns) do
    ~H"""
    <div class="col-span-3">
      <div
        :if={@allow_global}
        class="rounded-md bg-yellow-200 p-4 mb-4 border-2 border-slate-300"
      >
        <h3 class="text-sm font-medium text-yellow-800">
          <NewInputs.input
            type="checkbox"
            field={@form[:global]}
            label="Make client global (allow any project in this instance to use this client)"
          />
        </h3>
      </div>

      <div :if={!@global}>
        <label
          for={"project_oauth_clients_list_for_#{@form[:id].value}"}
          class={["block text-sm font-semibold leading-6 text-slate-800"]}
        >
          Project
        </label>

        <div class="flex w-full items-center gap-2 pb-3 mt-1">
          <div class="grow">
            <select
              id={"project_oauth_clients_list_for_#{@form[:id].value}"}
              name={:project_id}
              class={[
                "block w-full rounded-lg border border-secondary-300 bg-white",
                "sm:text-sm shadow-sm",
                "focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-opacity-50",
                "disabled:cursor-not-allowed "
              ]}
              phx-change="select_item"
              phx-target={@phx_target}
            >
              <option value="">
                Select a project to associate to this Oauth client
              </option>
              <%= Phoenix.HTML.Form.options_for_select(
                @available_projects
                |> Enum.map(fn %{id: id, name: name} -> {name, id} end),
                @selected
              ) %>
            </select>
          </div>

          <div class="grow-0 items-right">
            <.button
              id={"add-new-project-button-to-#{@form[:id].value}"}
              disabled={
                @selected == "" or @selected == nil or @available_projects == []
              }
              phx-target={@phx_target}
              phx-value-project_id={@selected}
              phx-click="add_new_project"
            >
              Add
            </.button>
          </div>
        </div>

        <div class="overflow-auto max-h-32">
          <span
            :for={project <- @selected_projects}
            class="inline-flex items-center gap-1 rounded-md bg-blue-100 px-4 mr-1 py-2 mb-2 text-gray-600"
          >
            <%= project.name %>
            <button
              id={"delete-project-oauth-client-#{project.id}-button"}
              phx-target={@phx_target}
              phx-value-project_id={project.id}
              phx-click="delete_project"
              type="button"
              class="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
            >
              <span class="sr-only">Remove</span>
              <svg
                viewBox="0 0 14 14"
                class="h-3.5 w-3.5 stroke-gray-700/50 group-hover:stroke-gray-700/75"
              >
                <path d="M4 4l6 6m0-6l-6 6" />
              </svg>
              <span class="absolute -inset-1"></span>
            </button>
          </span>
        </div>
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
      <NewInputs.input
        type="text"
        label={@label}
        field={@field}
        phx-hook="ClearInput"
      />
      <div>
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

  # defp project_name(projects, id) do
  #   Enum.find_value(projects, fn {name, project_id} ->
  #     if project_id == id, do: name
  #   end)
  # end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-10 sm:mt-0">
      <.modal id={@id} width="w-[32rem] lg:w-[44rem]">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold"><.modal_title action={@action} /></span>
            <button
              id={"close-oauth-client-modal-form-#{@oauth_client.id || "new"}"}
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
              <p class="text-sm text-gray-500 pt-2">
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
                  Manage Project Access
                </legend>
                <p class="text-sm text-gray-500 pt-2">
                  Control which projects have access to this credentials
                </p>
                <div class="mt-4">
                  <.project_oauth_clients
                    form={f}
                    available_projects={@available_projects}
                    selected_projects={@selected_projects}
                    projects={@projects}
                    selected={@selected_project}
                    allow_global={@allow_global}
                    global={@is_global}
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
