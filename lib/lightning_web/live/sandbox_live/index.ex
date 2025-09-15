defmodule LightningWeb.SandboxLive.Index do
  use LightningWeb, :live_view

  alias Ecto.Changeset
  alias Lightning.Projects
  alias LightningWeb.SandboxLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  @empty_changeset_types %{name: :string}

  defp confirm_changeset(sandbox, params \\ %{}) do
    data = %{}

    {data, @empty_changeset_types}
    |> Changeset.cast(params, [:name])
    |> Changeset.validate_required([:name])
    |> Changeset.validate_change(:name, fn :name, value ->
      if value == sandbox.name,
        do: [],
        else: [name: "must match the sandbox name"]
    end)
  end

  defp empty_confirm_changeset do
    Changeset.cast({%{}, @empty_changeset_types}, %{}, [:name])
  end

  defp load_workspace_projects(%{assigns: %{project: project}} = socket) do
    %{root: root_project, descendants: descendants} =
      Projects.list_workspace_projects(project.id)

    socket
    |> assign(:workspace_projects, [root_project | descendants])
    |> assign(:root_project, root_project)
    |> assign(:sandboxes, descendants)
  end

  defp reset_delete_modal_state(socket) do
    socket
    |> assign(:confirm_delete_open?, false)
    |> assign(:confirm_delete_sandbox, nil)
    |> assign(:confirm_delete_input, "")
    |> assign(:confirm_changeset, empty_confirm_changeset())
  end

  defp handle_sandbox_delete_result({:ok, _project}, sandbox, socket) do
    socket
    |> put_flash(:info, "Sandbox #{sandbox.name} deleted")
    |> reset_delete_modal_state()
    |> load_workspace_projects()
  end

  defp handle_sandbox_delete_result({:error, :unauthorized}, _sandbox, socket) do
    socket
    |> put_flash(:error, "You don't have permission to delete this sandbox")
    |> assign(:confirm_delete_open?, false)
  end

  defp handle_sandbox_delete_result({:error, :not_found}, _sandbox, socket) do
    socket
    |> put_flash(:error, "Sandbox not found")
    |> assign(:confirm_delete_open?, false)
  end

  defp handle_sandbox_delete_result({:error, reason}, _sandbox, socket) do
    socket
    |> put_flash(:error, "Failed to delete sandbox: #{inspect(reason)}")
    |> assign(:confirm_delete_open?, false)
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_menu_item, :sandboxes)
     |> reset_delete_modal_state()
     |> load_workspace_projects()}
  end

  @impl true
  def handle_params(
        %{"id" => id},
        _uri,
        %{assigns: %{workspace_projects: workspace_projects}} = socket
      )
      when socket.assigns.live_action == :edit do
    editing_sandbox = Enum.find(workspace_projects, &(&1.id == id))

    {:noreply, assign(socket, :editing_sandbox, editing_sandbox)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_workspace_projects(socket)}
  end

  @impl true
  def handle_event("open-delete-modal", %{"id" => sandbox_id}, socket) do
    case Enum.find(socket.assigns.sandboxes, &(&1.id == sandbox_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sandbox not found")}

      sandbox ->
        {:noreply,
         socket
         |> assign(:confirm_delete_open?, true)
         |> assign(:confirm_delete_sandbox, sandbox)
         |> assign(:confirm_delete_input, "")
         |> assign(:confirm_changeset, confirm_changeset(sandbox))}
    end
  end

  @impl true
  def handle_event("confirm-delete-validate", params, socket) do
    case socket.assigns.confirm_delete_sandbox do
      nil ->
        {:noreply, socket}

      sandbox ->
        confirm_params = params["confirm"] || %{}
        changeset = confirm_changeset(sandbox, confirm_params)
        input_name = String.trim(confirm_params["name"] || "")

        {:noreply,
         socket
         |> assign(:confirm_changeset, changeset)
         |> assign(:confirm_delete_input, input_name)}
    end
  end

  @impl true
  def handle_event("confirm-delete", params, socket) do
    %{
      project: parent_project,
      current_user: current_user,
      confirm_delete_sandbox: sandbox
    } = socket.assigns

    case sandbox do
      nil ->
        {:noreply, socket}

      sandbox ->
        confirm_params = params["confirm"] || %{}
        changeset = confirm_changeset(sandbox, confirm_params)

        if changeset.valid? do
          result =
            Lightning.Projects.delete_sandbox(
              parent_project,
              current_user,
              sandbox
            )

          updated_socket = handle_sandbox_delete_result(result, sandbox, socket)
          {:noreply, updated_socket}
        else
          {:noreply, assign(socket, :confirm_changeset, changeset)}
        end
    end
  end

  @impl true
  def handle_event("close-delete-modal", _params, socket) do
    {:noreply, reset_delete_modal_state(socket)}
  end

  @impl true
  def handle_info({:preview_theme, preview_style}, socket) do
    original_theme =
      socket.assigns[:original_theme_style] || socket.assigns.theme_style

    {:noreply,
     socket
     |> assign(:theme_style, preview_style || original_theme)
     |> assign(:original_theme_style, original_theme)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title>Sandboxes</:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <Components.header project={@project} />

        <Components.workspace_list
          root_project={@root_project}
          sandboxes={@sandboxes}
          project={@project}
          current_sandbox={@current_sandbox}
        />

        <Components.confirm_delete_modal
          open?={@confirm_delete_open?}
          sandbox={@confirm_delete_sandbox}
          changeset={@confirm_changeset}
        />

        <.live_component
          :if={@live_action == :new}
          module={LightningWeb.SandboxLive.FormComponent}
          id="sandbox-form-component-new"
          mode={:new}
          current_user={@current_user}
          parent={@current_sandbox || @project}
          return_to={nil}
        />

        <.live_component
          :if={@live_action == :edit and assigns[:editing_sandbox]}
          module={LightningWeb.SandboxLive.FormComponent}
          id={"sandbox-form-component-edit-#{@editing_sandbox.id}"}
          mode={:edit}
          sandbox={@editing_sandbox}
          current_user={@current_user}
          parent={@editing_sandbox.parent}
          return_to={~p"/projects/#{(@current_sandbox || @project).id}/sandboxes"}
        />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
