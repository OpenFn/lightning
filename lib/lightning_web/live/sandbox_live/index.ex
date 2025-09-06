defmodule LightningWeb.SandboxLive.Index do
  use LightningWeb, :live_view

  alias Ecto.Changeset
  alias Lightning.Projects
  alias LightningWeb.SandboxLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  defp confirm_changeset(sb, params \\ %{}) do
    data = %{}
    types = %{name: :string}

    {data, types}
    |> Changeset.cast(params, [:name])
    |> Changeset.validate_required([:name])
    |> Changeset.validate_change(:name, fn :name, val ->
      if val == sb.name, do: [], else: [name: "must match the sandbox name"]
    end)
  end

  defp empty_confirm_changeset do
    Changeset.cast({%{}, %{name: :string}}, %{}, [:name])
  end

  defp load_sandboxes(%{assigns: %{project: project}} = socket) do
    sandboxes = Projects.list_sandboxes(project.id)
    assign(socket, sandboxes: sandboxes)
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :sandboxes)
     |> assign(:confirm_delete_open?, false)
     |> assign(:confirm_delete_sandbox, nil)
     |> assign(:confirm_delete_input, "")
     |> assign(:confirm_cs, empty_confirm_changeset())
     |> load_sandboxes()}
  end

  @impl true
  def handle_params(
        %{"id" => id},
        _uri,
        %{assigns: %{sandboxes: sandboxes}} = socket
      )
      when socket.assigns.live_action == :edit do
    sb = Enum.find(sandboxes, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:sandbox, sb)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_sandboxes(socket)}
  end

  @impl true
  def handle_event("open-delete-modal", %{"id" => id}, socket) do
    sb = Enum.find(socket.assigns.sandboxes, &(&1.id == id))

    if sb do
      {:noreply,
       socket
       |> assign(:confirm_delete_open?, true)
       |> assign(:confirm_delete_sandbox, sb)
       |> assign(:confirm_delete_input, "")
       |> assign(:confirm_cs, confirm_changeset(sb))}
    else
      {:noreply, put_flash(socket, :error, "Sandbox not found")}
    end
  end

  @impl true
  def handle_event("confirm-delete-validate", params, socket) do
    sb = socket.assigns.confirm_delete_sandbox
    confirm = params["confirm"] || %{}

    if is_nil(sb) do
      {:noreply, socket}
    else
      cs = confirm_changeset(sb, confirm)
      name = String.trim(confirm["name"] || "")

      {:noreply, assign(socket, confirm_cs: cs, confirm_delete_input: name)}
    end
  end

  @impl true
  def handle_event("confirm-delete", params, socket) do
    parent = socket.assigns.project
    current = socket.assigns.current_user
    sb = socket.assigns.confirm_delete_sandbox
    confirm = params["confirm"] || %{}

    if is_nil(sb) do
      {:noreply, socket}
    else
      cs = confirm_changeset(sb, confirm)

      if cs.valid? do
        case Lightning.Projects.delete_sandbox(parent, current, sb) do
          {:ok, _proj} ->
            {:noreply,
             socket
             |> put_flash(:info, "Sandbox “#{sb.name}” deleted")
             |> assign(
               confirm_delete_open?: false,
               confirm_delete_sandbox: nil,
               confirm_delete_input: "",
               confirm_cs: empty_confirm_changeset()
             )
             |> load_sandboxes()}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "You don’t have permission to delete this sandbox"
             )
             |> assign(:confirm_delete_open?, false)}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Sandbox not found")
             |> assign(:confirm_delete_open?, false)}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to delete sandbox: #{inspect(reason)}")
             |> assign(:confirm_delete_open?, false)}
        end
      else
        {:noreply, assign(socket, :confirm_cs, cs)}
      end
    end
  end

  @impl true
  def handle_event("close-delete-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:confirm_delete_open?, false)
     |> assign(:confirm_delete_sandbox, nil)
     |> assign(:confirm_delete_input, "")
     |> assign(:confirm_cs, empty_confirm_changeset())}
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
        <Components.header project={@project} count={length(@sandboxes)} />

        <Components.list sandboxes={@sandboxes} project={@project} />
        <Components.confirm_delete_modal
          open?={@confirm_delete_open?}
          sandbox={@confirm_delete_sandbox}
          confirm_cs={@confirm_cs}
        />

        <.live_component
          :if={@live_action == :new}
          module={LightningWeb.SandboxLive.FormComponent}
          id="sandbox-new"
          mode={:new}
          current_user={@current_user}
          parent={@project}
          return_to={~p"/projects/#{@project.id}/sandboxes"}
        />

        <.live_component
          :if={@live_action == :edit}
          module={LightningWeb.SandboxLive.FormComponent}
          id={"sandbox-edit-#{@sandbox.id}"}
          mode={:edit}
          sandbox={@sandbox}
          current_user={@current_user}
          parent={@project}
          return_to={~p"/projects/#{@project.id}/sandboxes"}
        />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
