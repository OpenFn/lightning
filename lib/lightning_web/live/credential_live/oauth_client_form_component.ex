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
    :on_save,
    :button,
    :can_create_project_credential,
    :return_to
  ]

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(available_projects: [])}
  end

  @impl true
  def update(%{projects: projects} = assigns, socket) do
    changeset = OauthClients.change_client(assigns.oauth_client)
    all_projects = Enum.map(projects, &{&1.name, &1.id})

    initial_assigns =
      Map.filter(assigns, &match?({k, _} when k in @valid_assigns, &1))

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign(changeset: changeset)
     |> assign(all_projects: all_projects)
     |> assign(selected_project: nil)
     |> update_available_projects()}
  end

  @impl true
  def handle_event("validate", %{"oauth_client" => oauth_client_params}, socket) do
    changeset =
      OauthClients.change_client(
        socket.assigns.oauth_client,
        oauth_client_params
      )
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset)}
  end

  def handle_event(
        "select_item",
        %{"selected_project" => %{"id" => project_id}},
        socket
      ) do
    {:noreply, socket |> assign(selected_project: project_id)}
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
    {:noreply,
     socket
     |> push_navigate(to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
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
          id={"oauth-client-form-#{@oauth_client.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="space-y-6 bg-white px-4 py-5 sm:p-6">
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
                  field={f[:base_url]}
                  label="Server/Instance URL"
                  required="true"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:client_id]}
                  label="Client ID"
                  required="true"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:client_secret]}
                  label="Client Secret"
                />
              </div>
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

  defp save_oauth_client(socket, :edit, oauth_client_params) do
    %{oauth_client: form_oauth_client} = socket.assigns

    case OauthClients.update_client(form_oauth_client, oauth_client_params) do
      {:ok, _oauth_client} ->
        {:noreply,
         socket
         |> put_flash(:info, "Oauth client updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_oauth_client(socket, :new, oauth_client_params) do
    user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)

    project_oauth_clients =
      Ecto.Changeset.fetch_field!(
        socket.assigns.changeset,
        :project_oauth_clients
      )
      |> Enum.map(fn %{project_id: project_id} ->
        %{"project_id" => project_id}
      end)

    oauth_client_params
    |> Map.put("user_id", user_id)
    |> Map.put("project_oauth_clients", project_oauth_clients)
    |> OauthClients.create_client()
    |> case do
      {:ok, oauth_client} ->
        if socket.assigns[:on_save] do
          socket.assigns[:on_save].(oauth_client)
          {:noreply, push_event(socket, "close_modal", %{})}
        else
          {:noreply,
           socket
           |> put_flash(:info, "Oauth client created successfully")
           |> push_redirect(to: socket.assigns.return_to)}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp filter_available_projects(changeset, all_projects) do
    existing_ids =
      fetch_field!(changeset, :project_oauth_clients)
      |> Enum.reject(fn poc -> poc.delete end)
      |> Enum.map(fn poc -> poc.oauth_client_id end)

    all_projects
    |> Enum.reject(fn {_, oauth_client_id} -> oauth_client_id in existing_ids end)
  end
end
