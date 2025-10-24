defmodule LightningWeb.SandboxLive.Index do
  use LightningWeb, :live_view

  alias Ecto.Changeset
  alias Lightning.Projects
  alias Lightning.Projects.MergeProjects
  alias Lightning.Projects.ProjectLimiter
  alias LightningWeb.SandboxLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  @empty_changeset_types %{name: :string}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_menu_item, :sandboxes)
     |> assign(
       :limit_new_sandbox,
       ProjectLimiter.limit_new_sandbox(socket.assigns.project.id)
     )
     |> reset_delete_modal_state()
     |> reset_merge_modal_state()
     |> load_workspace_projects()}
  end

  @impl true
  def handle_params(
        %{"id" => id},
        _uri,
        %{
          assigns: %{
            sandboxes: sandboxes,
            project: project,
            live_action: live_action
          }
        } = socket
      )
      when live_action == :edit do
    case Enum.find(sandboxes, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sandbox not found")}

      sandbox ->
        if sandbox.can_edit do
          {:noreply, assign(socket, :editing_sandbox, sandbox)}
        else
          {:noreply,
           socket
           |> put_flash(:error, "You are not authorized to edit this sandbox")
           |> push_navigate(to: ~p"/projects/#{project.id}/sandboxes")}
        end
    end
  end

  def handle_params(
        _params,
        _uri,
        %{
          assigns: %{
            limit_new_sandbox: limit_new_sandbox,
            can_create_sandbox: can_create_sandbox,
            project: project,
            live_action: live_action
          }
        } = socket
      )
      when live_action == :new do
    case {can_create_sandbox, limit_new_sandbox} do
      {true, :ok} ->
        load_workspace_projects(socket)

      {false, _} ->
        socket
        |> put_flash(
          :error,
          "You are not authorized to create sandboxes in this workspace"
        )
        |> push_navigate(to: ~p"/projects/#{project.id}/sandboxes")

      {_, {:error, _, %{text: text}}} ->
        socket
        |> put_flash(:error, text)
        |> push_navigate(to: ~p"/projects/#{project.id}/sandboxes")
    end
    |> noreply()
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
        if sandbox.can_delete do
          {:noreply,
           socket
           |> assign(:confirm_delete_open?, true)
           |> assign(:confirm_delete_sandbox, sandbox)
           |> assign(:confirm_delete_input, "")
           |> assign(:confirm_changeset, confirm_changeset(sandbox))}
        else
          {:noreply,
           socket
           |> put_flash(:error, "You are not authorized to delete this sandbox")}
        end
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
  def handle_event(
        "confirm-delete",
        params,
        %{
          assigns: %{
            current_user: current_user,
            confirm_delete_sandbox: sandbox
          }
        } = socket
      ) do
    case sandbox do
      nil ->
        {:noreply, socket}

      sandbox ->
        confirm_params = params["confirm"] || %{}
        changeset = confirm_changeset(sandbox, confirm_params)

        if changeset.valid? do
          {:noreply,
           Lightning.Projects.delete_sandbox(
             sandbox,
             current_user
           )
           |> handle_sandbox_delete_result(sandbox, socket)}
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
  def handle_event("open-merge-modal", %{"id" => sandbox_id}, socket) do
    case Enum.find(socket.assigns.sandboxes, &(&1.id == sandbox_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sandbox not found")}

      sandbox ->
        if sandbox.can_merge do
          target_options = get_merge_target_options(socket, sandbox)

          default_target =
            Enum.find(target_options, &(&1.value == sandbox.parent_id))

          descendants =
            get_all_descendants(sandbox, socket.assigns.workspace_projects)

          merge_changeset =
            merge_changeset(%{
              target_id: default_target && default_target.value
            })

          has_diverged =
            if default_target do
              target_project =
                Enum.find(
                  socket.assigns.workspace_projects,
                  &(&1.id == default_target.value)
                )

              target_project &&
                MergeProjects.has_diverged?(
                  sandbox,
                  target_project
                )
            else
              false
            end

          {:noreply,
           socket
           |> assign(:merge_modal_open?, true)
           |> assign(:merge_source_sandbox, sandbox)
           |> assign(:merge_target_options, target_options)
           |> assign(:merge_changeset, merge_changeset)
           |> assign(:merge_descendants, descendants)
           |> assign(:merge_has_diverged, has_diverged)}
        else
          {:noreply,
           socket
           |> put_flash(:error, "You are not authorized to merge this sandbox")}
        end
    end
  end

  @impl true
  def handle_event("close-merge-modal", _params, socket) do
    {:noreply, reset_merge_modal_state(socket)}
  end

  @impl true
  def handle_event(
        "select-merge-target",
        %{"merge" => %{"target_id" => target_id}},
        socket
      ) do
    merge_changeset = merge_changeset(%{target_id: target_id})

    has_diverged =
      if target_id do
        source = socket.assigns.merge_source_sandbox

        target_project =
          Enum.find(
            socket.assigns.workspace_projects,
            &(&1.id == target_id)
          )

        target_project &&
          MergeProjects.has_diverged?(source, target_project)
      else
        false
      end

    {:noreply,
     socket
     |> assign(:merge_changeset, merge_changeset)
     |> assign(:merge_has_diverged, has_diverged)}
  end

  @impl true
  def handle_event(
        "confirm-merge",
        %{"merge" => %{"target_id" => target_id}},
        %{
          assigns: %{
            merge_source_sandbox: source,
            current_user: actor,
            root_project: root_project
          }
        } = socket
      ) do
    cond do
      is_nil(source) ->
        socket
        |> put_flash(:error, "Invalid merge request")
        |> reset_merge_modal_state()
        |> noreply()

      not source.can_merge ->
        socket
        |> put_flash(:error, "You are not authorized to merge this sandbox")
        |> reset_merge_modal_state()
        |> noreply()

      true ->
        socket.assigns.workspace_projects
        |> find_target_project(target_id)
        |> case do
          nil ->
            socket
            |> put_flash(:error, "Target project not found")
            |> reset_merge_modal_state()
            |> noreply()

          target ->
            source
            |> perform_merge(target, actor)
            |> handle_merge_result(socket, source, target, root_project, actor)
        end
    end
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
        <LayoutComponents.header current_user={@current_user} project={@project}>
          <:title>Sandboxes</:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <Components.header
          current_project={@project}
          enable_create_button={@can_create_sandbox and @limit_new_sandbox == :ok}
          disabled_button_tooltip={
            create_sandbox_tooltip_message(
              @can_create_sandbox,
              @limit_new_sandbox
            )
          }
        />

        <Components.workspace_list
          root_project={@root_project}
          current_project={@project}
          sandboxes={@sandboxes}
          enable_create_button={@can_create_sandbox and @limit_new_sandbox == :ok}
          disabled_button_tooltip={
            create_sandbox_tooltip_message(@can_create_sandbox, @limit_new_sandbox)
          }
        />

        <Components.confirm_delete_modal
          :if={@confirm_delete_sandbox}
          open?={@confirm_delete_open?}
          sandbox={@confirm_delete_sandbox}
          changeset={@confirm_changeset}
          root_project={@root_project}
        />

        <Components.merge_modal
          :if={@merge_source_sandbox}
          open?={@merge_modal_open?}
          sandbox={@merge_source_sandbox}
          target_options={@merge_target_options}
          changeset={@merge_changeset}
          descendants={@merge_descendants}
          has_diverged={@merge_has_diverged}
        />

        <.live_component
          :if={@live_action == :new}
          module={LightningWeb.SandboxLive.FormComponent}
          id="sandbox-form-component-new"
          mode={:new}
          current_user={@current_user}
          parent={@project}
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
          return_to={~p"/projects/#{@project.id}/sandboxes"}
        />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  defp load_workspace_projects(%{assigns: %{project: project}} = socket) do
    %{root: root_project, descendants: descendants} =
      Projects.list_workspace_projects(project.id)

    current_user = socket.assigns.current_user

    can_create_sandbox =
      Lightning.Policies.Permissions.can?(
        :sandboxes,
        :provision_sandbox,
        current_user,
        project
      )

    manage_permissions =
      Lightning.Policies.Sandboxes.check_manage_permissions(
        descendants,
        current_user,
        root_project
      )

    sandboxes =
      Enum.map(descendants, fn sandbox ->
        perms =
          Map.get(manage_permissions, sandbox.id, %{
            update: false,
            delete: false,
            merge: false
          })

        sandbox
        |> Map.put(:can_edit, perms.update)
        |> Map.put(:can_delete, perms.delete)
        |> Map.put(:can_merge, perms.merge)
        |> Map.put(:is_current, project.id == sandbox.id)
      end)

    socket
    |> assign(:workspace_projects, [root_project | descendants])
    |> assign(:root_project, root_project)
    |> assign(:sandboxes, sandboxes)
    |> assign(:can_create_sandbox, can_create_sandbox)
  end

  defp reset_delete_modal_state(socket) do
    socket
    |> assign(:confirm_delete_open?, false)
    |> assign(:confirm_delete_sandbox, nil)
    |> assign(:confirm_delete_input, "")
    |> assign(:confirm_changeset, empty_confirm_changeset())
  end

  defp reset_merge_modal_state(socket) do
    socket
    |> assign(:merge_modal_open?, false)
    |> assign(:merge_source_sandbox, nil)
    |> assign(:merge_changeset, merge_changeset())
    |> assign(:merge_target_options, [])
    |> assign(:merge_descendants, [])
    |> assign(:merge_has_diverged, false)
  end

  defp merge_changeset(params \\ %{}) do
    types = %{target_id: :string}

    {%{}, types}
    |> Changeset.cast(params, [:target_id])
    |> Changeset.validate_required([:target_id])
  end

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

  defp handle_sandbox_delete_result(
         {:ok, _project},
         deleted_sandbox,
         %{assigns: %{project: current_project, root_project: root_project}} =
           socket
       ) do
    should_redirect =
      current_project.id == deleted_sandbox.id or
        Projects.descendant_of?(
          current_project,
          deleted_sandbox,
          root_project
        )

    socket_to_return =
      socket
      |> put_flash(
        :info,
        "Sandbox #{deleted_sandbox.name} and all its associated descendants deleted"
      )
      |> reset_delete_modal_state()

    if should_redirect do
      push_navigate(socket_to_return, to: ~p"/projects/#{root_project.id}/w")
    else
      load_workspace_projects(socket_to_return)
    end
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

  defp get_merge_target_options(socket, source_sandbox) do
    root_project = socket.assigns.root_project

    socket.assigns.workspace_projects
    |> Enum.reject(fn potential_target ->
      potential_target.id == source_sandbox.id or
        Projects.descendant_of?(potential_target, source_sandbox, root_project)
    end)
    |> Enum.map(fn project ->
      %{
        value: project.id,
        label: project.name
      }
    end)
  end

  defp get_all_descendants(sandbox, workspace_projects) do
    project_map = Map.new(workspace_projects, &{&1.id, &1})

    workspace_projects
    |> Enum.filter(fn project ->
      descendant_of?(project.parent_id, sandbox.id, project_map)
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp descendant_of?(nil, _ancestor_id, _project_map), do: false

  defp descendant_of?(parent_id, ancestor_id, _project_map)
       when parent_id == ancestor_id,
       do: true

  defp descendant_of?(parent_id, ancestor_id, project_map) do
    case Map.get(project_map, parent_id) do
      nil ->
        false

      parent ->
        descendant_of?(parent.parent_id, ancestor_id, project_map)
    end
  end

  defp find_target_project(workspace_projects, target_id) do
    Enum.find(workspace_projects, &(&1.id == target_id))
  end

  defp perform_merge(source, target, actor) do
    source
    |> MergeProjects.merge_project(target)
    |> then(
      &Lightning.Projects.Provisioner.import_document(target, actor, &1,
        allow_stale: true
      )
    )
  end

  defp handle_merge_result(
         {:ok, _updated_target},
         socket,
         source,
         target,
         _root_project,
         actor
       ) do
    flash_message = build_merge_success_message(source, target, actor)

    socket
    |> put_flash(:info, flash_message)
    |> reset_merge_modal_state()
    |> push_navigate(to: ~p"/projects/#{target.id}/w")
    |> noreply()
  end

  defp handle_merge_result(
         {:error, reason},
         socket,
         _source,
         _target,
         _root,
         _actor
       ) do
    socket
    |> put_flash(:error, format_merge_error(reason))
    |> reset_merge_modal_state()
    |> noreply()
  end

  defp build_merge_success_message(source, target, actor) do
    case Lightning.Projects.delete_sandbox(source, actor) do
      {:ok, _} ->
        "Successfully merged #{source.name} into #{target.name} and deleted the sandbox"

      {:error, _} ->
        "Successfully merged #{source.name} into #{target.name}, but could not delete the sandbox"
    end
  end

  defp create_sandbox_tooltip_message(can_create_sandbox, limiter_result) do
    case {can_create_sandbox, limiter_result} do
      {false, _} ->
        "You are not authorized to create sandboxes in this workspace"

      {_, {:error, _, %{text: text}}} ->
        text

      _other ->
        nil
    end
  end

  defp format_merge_error(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> List.first()
    |> case do
      {field, {message, _}} -> "#{field}: #{message}"
      _ -> "Failed to merge: validation error"
    end
  end

  defp format_merge_error(%{text: text}), do: text
  defp format_merge_error(reason), do: "Failed to merge: #{inspect(reason)}"
end
