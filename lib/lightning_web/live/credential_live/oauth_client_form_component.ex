defmodule LightningWeb.CredentialLive.OauthClientFormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.OauthClients
  alias LightningWeb.Components.NewInputs
  alias LightningWeb.CredentialLive.Helpers
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
      Helpers.filter_available_projects(
        projects,
        selected_projects
      )

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

    available_projects =
      Helpers.filter_available_projects(
        socket.assigns.projects,
        socket.assigns.selected_projects
      )

    is_global = Ecto.Changeset.fetch_field!(changeset, :global)

    {:noreply,
     assign(socket,
       changeset: changeset,
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
        "select_project",
        %{"project_id" => project_id},
        socket
      ) do
    {:noreply,
     socket
     |> assign(selected_project: project_id)
     |> push_event("clear_input", %{})}
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
     |> assign(selected_project: nil)
     |> push_event("clear_input", %{})}
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
      Helpers.prepare_projects_associations(
        socket.assigns.changeset,
        socket.assigns.selected_projects,
        :project_oauth_clients
      )

    params =
      oauth_client_params
      |> Map.put("project_oauth_clients", project_oauth_clients)
      |> add_scopes_to_params(socket)

    case mode do
      :edit ->
        update_oauth_client(socket, params)

      :new ->
        user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)
        params = Map.put(params, "user_id", user_id)
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
                  field={f[:introspection_endpoint]}
                  label="Introspection URL"
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
                on_edit="EditScope"
                event_type="edit_mandatory_scope"
                scopes={@mandatory_scopes}
                phx_target={@myself}
              />

              <.scopes_input
                id={"optional-scopes-#{@oauth_client.id || "new"}"}
                field={f[:optional_scopes]}
                label="Optional Scopes"
                on_delete="remove_optional_scope"
                on_edit="EditScope"
                event_type="edit_optional_scope"
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
                  Control which projects have access to this OAuth client
                </p>
                <div class="mt-4">
                  <.global_client_checkbox :if={@allow_global} form={f} />
                  <LightningWeb.Components.Credentials.projects_picker
                    :if={!@is_global}
                    id={@oauth_client.id || "new"}
                    type={:oauth_client}
                    available_projects={@available_projects}
                    selected_projects={@selected_projects}
                    projects={@projects}
                    selected={@selected_project}
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
                    Add OAuth Client
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

  attr :form, :any, required: true

  def global_client_checkbox(assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-200 p-4 mb-4 border-2 border-slate-300">
      <h3 class="text-sm font-medium text-yellow-800">
        <NewInputs.input
          type="checkbox"
          field={@form[:global]}
          label="Make client global (allow any project in this instance to use this client)"
        />
      </h3>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :scopes, :list, required: true
  attr :label, :string, required: true
  attr :field, :any, required: true
  attr :on_delete, :string, required: true
  attr :on_edit, :string, required: true
  attr :event_type, :string, required: true
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
          data-event-type={@event_type}
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
      Edit OAuth Client
    <% else %>
      Add an OAuth Client
    <% end %>
    """
  end
end
