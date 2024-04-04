defmodule LightningWeb.CredentialLive.OauthClientFormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]

  alias Lightning.Credentials
  alias LightningWeb.Components.NewInputs
  alias Phoenix.LiveView.JS

  @valid_assigns [
    :id,
    :action,
    :credential,
    :current_user,
    :projects,
    :on_save,
    :button,
    :show_project_credentials,
    :can_create_project_credential,
    :return_to
  ]

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(available_projects: [])}
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

  def update(%{projects: projects} = assigns, socket) do
    users = list_users()

    changeset = Credentials.change_credential(assigns.credential)
    all_projects = Enum.map(projects, &{&1.name, &1.id})

    initial_assigns =
      Map.filter(assigns, &match?({k, _} when k in @valid_assigns, &1))

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign(users: users)
     |> assign(changeset: changeset)
     |> assign(all_projects: all_projects)
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
          id={"credential-form-#{@credential.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="space-y-6 bg-white px-4 py-5 sm:p-6">
            <div class="space-y-4">
              <div>
                <NewInputs.input type="text" field={f[:name]} label="Name" />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input
                  type="text"
                  field={f[:name]}
                  label="Server/Instance URL"
                />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input type="text" field={f[:name]} label="Client ID" />
              </div>
            </div>

            <div class="space-y-4">
              <div>
                <NewInputs.input type="text" field={f[:name]} label="Client Secret" />
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
                  <.project_credentials
                    form={f}
                    projects={@all_projects}
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
                disabled={!@changeset.valid? or @scopes_changed}
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

  defp list_users do
    Lightning.Accounts.list_users()
    |> Enum.map(fn user ->
      [
        key: "#{user.first_name} #{user.last_name} (#{user.email})",
        value: user.id
      ]
    end)
  end

  defp modal_title(assigns) do
    ~H"""
    <%= if @action in [:edit] do %>
      Edit an Oauth Client
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

  defp save_credential(
         socket,
         :edit,
         credential_params
       ) do
    %{credential: form_credential} = socket.assigns

    with {:uptodate, true} <-
           {:uptodate, credential_projects_up_to_date?(form_credential)},
         {:same_user, true} <-
           {:same_user,
            socket.assigns.current_user.id == socket.assigns.credential.user_id},
         {:ok, _credential} <-
           Credentials.update_credential(form_credential, credential_params) do
      {:noreply,
       socket
       |> put_flash(:info, "Credential updated successfully")
       |> push_redirect(to: socket.assigns.return_to)}
    else
      {:uptodate, false} ->
        credential = Credentials.get_credential_for_update!(form_credential.id)

        {:noreply,
         socket
         |> assign(credential: credential)
         |> put_flash(
           :error,
           "Credential was updated by another session. Please try again."
         )
         |> push_redirect(to: socket.assigns.return_to)}

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

  defp filter_available_projects(changeset, all_projects) do
    existing_ids =
      fetch_field!(changeset, :project_credentials)
      |> Enum.reject(fn pu -> pu.delete end)
      |> Enum.map(fn pu -> pu.credential_id end)

    all_projects
    |> Enum.reject(fn {_, credential_id} -> credential_id in existing_ids end)
  end

  defp credential_projects_up_to_date?(form_credential) do
    db_credential = Credentials.get_credential_for_update!(form_credential.id)

    Map.get(db_credential, :project_credentials) ==
      Map.get(form_credential, :project_credentials)
  end
end
