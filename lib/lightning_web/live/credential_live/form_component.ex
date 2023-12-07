defmodule LightningWeb.CredentialLive.FormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.Credentials

  alias LightningWeb.CredentialLive.{
    RawBodyComponent,
    JsonSchemaBodyComponent,
    GoogleSheetsComponent
  }

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]

  # NOTE: this function is sometimes called from inside a Task and therefore
  # requires a `pid`
  defp update_body(pid, id, body) do
    send_update(pid, __MODULE__, id: id, body: body)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"credential-#{@id}"} class="@container">
      <.live_component
        :if={!@type}
        module={LightningWeb.CredentialLive.TypePicker}
        id={"#{@id}-type-picker"}
        on_confirm="type_selected"
        phx_target={@myself}
      />
      <div :if={@type} class="mt-10 sm:mt-0">
        <div class="lg:grid md:grid-cols-3 md:gap-6">
          <div class="md:col-span-1 hidden @2xl:block">
            <div class="px-4 sm:px-0">
              <p class="mt-1 text-sm text-gray-600">
                Configure your credential
              </p>
            </div>
          </div>

          <div class="md:col-span-2">
            <div class="mt-5 md:col-span-2 md:mt-0">
              <div class="overflow-hidden shadow sm:rounded-md">
                <.form
                  :let={f}
                  for={@changeset}
                  id="credential-form"
                  phx-target={@myself}
                  phx-change="validate"
                  phx-submit="save"
                >
                  <.form_component
                    :let={{fieldset, valid?}}
                    form={f}
                    type={@type}
                    update_body={@update_body}
                  >
                    <div class="space-y-6 bg-white px-4 py-5 sm:p-6">
                      <fieldset>
                        <div class="space-y-4">
                          <div>
                            <LightningWeb.Components.Form.text_field
                              form={f}
                              field={:name}
                            />
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

                    <div class="bg-gray-50 px-4 py-3 sm:px-6">
                      <div class="flex flex-rows">
                        <div :for={button <- @button} class={button[:class]}>
                          <%= render_slot(button, valid?) %>
                        </div>
                      </div>
                    </div>
                  </.form_component>
                </.form>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Switcher components for different types of credentials.
  """

  attr(:type, :string, required: true)
  attr(:form, :map, required: true)
  attr(:update_body, :any, required: false)
  slot(:inner_block)

  def form_component(%{type: "googlesheets"} = assigns) do
    ~H"""
    <GoogleSheetsComponent.fieldset :let={l} form={@form} update_body={@update_body}>
      <%= render_slot(@inner_block, l) %>
    </GoogleSheetsComponent.fieldset>
    """
  end

  def form_component(%{type: "raw"} = assigns) do
    ~H"""
    <RawBodyComponent.fieldset :let={l} form={@form}>
      <%= render_slot(@inner_block, l) %>
    </RawBodyComponent.fieldset>
    """
  end

  def form_component(%{type: _schema} = assigns) do
    ~H"""
    <JsonSchemaBodyComponent.fieldset :let={l} form={@form}>
      <%= render_slot(@inner_block, l) %>
    </JsonSchemaBodyComponent.fieldset>
    """
  end

  attr(:form, :map, required: true)
  attr(:projects, :list, required: true)
  attr(:selected, :map, required: true)
  attr(:phx_target, :any, default: nil)

  def project_credentials(assigns) do
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
            id="project_list"
          />
        </div>
        <div class="grow-0 items-right">
          <.button
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
                phx-value-index={project_credential.index}
                phx-click="delete_project"
              >
                Remove
              </.button>
            </div>
          </div>
        <% end %>
        <.input type="hidden" field={project_credential[:project_id]} />
        <.input type="hidden" field={project_credential[:delete]} />
      </.inputs_for>
    </div>
    """
  end

  defp project_name(projects, id) do
    Enum.find_value(projects, fn {name, project_id} ->
      if project_id == id, do: name
    end)
  end

  attr(:users, :list, required: true)
  attr(:form, :map, required: true)

  def credential_transfer(assigns) do
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

  @impl true
  def mount(socket) do
    allow_credential_transfer =
      Application.fetch_env!(:lightning, LightningWeb)
      |> Keyword.get(:allow_credential_transfer)

    {:ok,
     socket
     |> assign(
       allow_credential_transfer: allow_credential_transfer,
       available_projects: [],
       type: nil,
       button: []
     )}
  end

  @valid_assigns [
    :id,
    :action,
    :credential,
    :projects,
    :on_save,
    :button,
    :show_project_credentials,
    :return_to
  ]

  @impl true
  def update(%{body: body}, socket) do
    {:ok,
     socket
     |> update(:changeset, fn changeset, %{credential: credential} ->
       params =
         changeset.params
         |> Map.put("body", body)

       Credentials.change_credential(credential, params)
     end)}
  end

  def update(%{projects: projects} = assigns, socket) do
    pid = self()

    {:ok,
     socket
     |> assign(
       assigns
       |> Map.filter(&match?({k, _} when k in @valid_assigns, &1))
     )
     |> assign_new(:show_project_credentials, fn -> true end)
     |> assign(
       changeset: Credentials.change_credential(assigns.credential),
       all_projects: projects |> Enum.map(&{&1.name, &1.id}),
       selected_project: "",
       users:
         Enum.map(Lightning.Accounts.list_users(), fn user ->
           [
             key: "#{user.first_name} #{user.last_name} (#{user.email})",
             value: user.id
           ]
         end),
       schema: nil,
       update_body: fn body ->
         update_body(pid, assigns.id, body)
       end
     )
     |> update(:type, fn _, %{changeset: changeset} ->
       changeset |> Ecto.Changeset.fetch_field!(:schema)
     end)
     |> update(
       :available_projects,
       fn _,
          %{
            all_projects: all_projects,
            changeset: changeset
          } ->
         filter_available_projects(changeset, all_projects)
       end
     )}
  end

  @impl true
  def handle_event("validate", %{"credential" => credential_params}, socket) do
    changeset =
      Credentials.change_credential(
        socket.assigns.credential,
        credential_params |> Map.put("schema", socket.assigns.type)
      )
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event("type_selected", %{"selected" => type}, socket) do
    changeset =
      Credentials.change_credential(socket.assigns.credential, %{schema: type})

    {:noreply, socket |> assign(type: type, changeset: changeset)}
  end

  @impl true
  def handle_event(
        "select_item",
        %{"selected_project" => %{"id" => project_id}},
        socket
      ) do
    {:noreply, socket |> assign(selected_project: project_id)}
  end

  @impl true
  def handle_event("add_new_project", %{"projectid" => project_id}, socket) do
    project_credentials =
      fetch_field!(socket.assigns.changeset, :project_credentials)

    project_credentials =
      Enum.find(project_credentials, fn pu -> pu.project_id == project_id end)
      |> if do
        project_credentials
        |> Enum.map(fn pu ->
          if pu.project_id == project_id do
            Ecto.Changeset.change(pu, %{delete: false})
          end
        end)
      else
        project_credentials
        |> Enum.concat([
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
       selected_project: ""
     )}
  end

  @impl true
  def handle_event("delete_project", %{"index" => index}, socket) do
    index = String.to_integer(index)

    project_credentials_params =
      fetch_field!(socket.assigns.changeset, :project_credentials)
      |> Enum.with_index()
      |> Enum.reduce([], fn {pu, i}, project_credentials ->
        if i == index do
          if is_nil(pu.id) do
            project_credentials
          else
            [Ecto.Changeset.change(pu, %{delete: true}) | project_credentials]
          end
        else
          [pu | project_credentials]
        end
      end)

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_credentials, project_credentials_params)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(changeset: changeset, available_projects: available_projects)}
  end

  def handle_event("save", %{"credential" => credential_params}, socket) do
    save_credential(
      socket,
      socket.assigns.action,
      credential_params
    )
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

  defp save_credential(socket, :new, credential_params) do
    %{changeset: changeset, type: schema_name} = socket.assigns

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
          {:noreply, socket}
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
