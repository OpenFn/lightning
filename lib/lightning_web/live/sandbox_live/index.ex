defmodule LightningWeb.SandboxLive.Index do
  use LightningWeb, :live_view

  alias Ecto.Changeset
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.MergeProjects
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.Sandboxes
  alias Lightning.Repo
  alias Lightning.VersionControl
  alias LightningWeb.SandboxLive.Components

  defmodule MergeWorkflow do
    defstruct [:id, :name, :is_diverged, :is_new, :is_deleted]
  end

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

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

          diverged_workflows =
            get_diverged_workflows(
              sandbox,
              default_target && default_target.value,
              socket.assigns.workspace_projects
            )

          target_project =
            Enum.find(
              socket.assigns.workspace_projects,
              fn project ->
                project.id == (default_target && default_target.value)
              end
            )

          source_workflows =
            build_merge_workflow_list(
              sandbox,
              diverged_workflows,
              target_project
            )

          selected_ids = MapSet.new(source_workflows, fn wf -> wf.id end)

          {:noreply,
           socket
           |> assign(:merge_modal_open?, true)
           |> assign(:merge_source_sandbox, sandbox)
           |> assign(:merge_target_options, target_options)
           |> assign(:merge_changeset, merge_changeset)
           |> assign(:merge_descendants, descendants)
           |> assign(:merge_diverged_workflows, diverged_workflows)
           |> assign(:merge_source_workflows, source_workflows)
           |> assign(:merge_selected_workflow_ids, selected_ids)}
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
  def handle_event("toggle-workflow", %{"id" => workflow_id}, socket) do
    selected = socket.assigns.merge_selected_workflow_ids

    new_selected =
      if MapSet.member?(selected, workflow_id) do
        MapSet.delete(selected, workflow_id)
      else
        MapSet.put(selected, workflow_id)
      end

    {:noreply, assign(socket, :merge_selected_workflow_ids, new_selected)}
  end

  @impl true
  def handle_event("toggle-all-workflows", _params, socket) do
    all_ids =
      MapSet.new(socket.assigns.merge_source_workflows, fn wf -> wf.id end)

    new_selected =
      if MapSet.equal?(socket.assigns.merge_selected_workflow_ids, all_ids) do
        MapSet.new()
      else
        all_ids
      end

    {:noreply, assign(socket, :merge_selected_workflow_ids, new_selected)}
  end

  @impl true
  def handle_event(
        "select-merge-target",
        %{"merge" => %{"target_id" => target_id}},
        socket
      ) do
    merge_changeset = merge_changeset(%{target_id: target_id})

    diverged_workflows =
      get_diverged_workflows(
        socket.assigns.merge_source_sandbox,
        target_id,
        socket.assigns.workspace_projects
      )

    target_project =
      Enum.find(socket.assigns.workspace_projects, fn project ->
        project.id == target_id
      end)

    source_workflows =
      if target_project do
        build_merge_workflow_list(
          socket.assigns.merge_source_sandbox,
          diverged_workflows,
          target_project
        )
      else
        socket.assigns.merge_source_workflows
      end

    all_ids = MapSet.new(source_workflows, fn wf -> wf.id end)

    prev_ids =
      MapSet.new(socket.assigns.merge_source_workflows, fn wf -> wf.id end)

    selected_ids =
      socket.assigns.merge_selected_workflow_ids
      |> MapSet.intersection(all_ids)
      |> MapSet.union(MapSet.difference(all_ids, prev_ids))

    {:noreply,
     socket
     |> assign(:merge_changeset, merge_changeset)
     |> assign(:merge_diverged_workflows, diverged_workflows)
     |> assign(:merge_source_workflows, source_workflows)
     |> assign(:merge_selected_workflow_ids, selected_ids)}
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
            if Permissions.can?(
                 :sandboxes,
                 :merge_sandbox,
                 actor,
                 target
               ) do
              selected_ids =
                resolve_selected_workflow_ids(socket.assigns)

              source
              |> perform_merge(target, actor, selected_ids)
              |> handle_merge_result(socket, source, target, root_project, actor)
            else
              socket
              |> put_flash(
                :error,
                "You are not authorized to merge into this project"
              )
              |> reset_merge_modal_state()
              |> noreply()
            end
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
      <:banner>
        <Common.dynamic_component
          :if={assigns[:banner]}
          function={@banner.function}
          args={@banner.attrs}
        />
      </:banner>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:breadcrumbs>
            <LayoutComponents.breadcrumbs>
              <LayoutComponents.breadcrumb_project_picker label={@project.name} />
              <LayoutComponents.breadcrumb>
                <:label>Sandboxes</:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
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
          diverged_workflows={@merge_diverged_workflows}
          source_workflows={@merge_source_workflows}
          selected_workflow_ids={@merge_selected_workflow_ids}
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
      Permissions.can?(
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
    |> assign(:merge_diverged_workflows, [])
    |> assign(:merge_source_workflows, [])
    |> assign(:merge_selected_workflow_ids, MapSet.new())
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
    current_user = socket.assigns.current_user
    root_project = socket.assigns.root_project

    socket.assigns.workspace_projects
    |> Enum.reject(fn potential_target ->
      potential_target.id == source_sandbox.id or
        Projects.descendant_of?(potential_target, source_sandbox, root_project)
    end)
    |> Enum.filter(fn project ->
      user_role_on_project(project, current_user) in [:owner, :admin, :editor] or
        current_user.role == :superuser
    end)
    |> Enum.map(fn project ->
      %{
        value: project.id,
        label: project.name
      }
    end)
  end

  defp user_role_on_project(project, user) do
    case Enum.find(project.project_users, &(&1.user_id == user.id)) do
      nil -> nil
      pu -> pu.role
    end
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
    Enum.find(workspace_projects, fn project -> project.id == target_id end)
  end

  defp build_merge_workflow_list(source, _diverged_names, nil) do
    source
    |> Repo.preload(:workflows)
    |> Map.get(:workflows, [])
    |> Enum.map(fn wf ->
      %MergeWorkflow{
        id: wf.id,
        name: wf.name,
        is_diverged: false,
        is_new: true,
        is_deleted: false
      }
    end)
    |> Enum.sort_by(fn wf -> wf.name end)
  end

  defp build_merge_workflow_list(source, diverged_names, target_project) do
    target_workflows =
      target_project
      |> Repo.preload(:workflows)
      |> Map.get(:workflows, [])

    target_workflow_names = MapSet.new(target_workflows, fn wf -> wf.name end)

    diverged_set = MapSet.new(diverged_names)

    source_workflows =
      source
      |> Repo.preload(:workflows)
      |> Map.get(:workflows, [])

    source_workflow_names = MapSet.new(source_workflows, fn wf -> wf.name end)

    source_entries =
      Enum.map(source_workflows, fn wf ->
        %MergeWorkflow{
          id: wf.id,
          name: wf.name,
          is_diverged: MapSet.member?(diverged_set, wf.name),
          is_new: not MapSet.member?(target_workflow_names, wf.name),
          is_deleted: false
        }
      end)

    deleted_entries =
      target_workflows
      |> Enum.reject(fn wf -> MapSet.member?(source_workflow_names, wf.name) end)
      |> Enum.map(fn wf ->
        %MergeWorkflow{
          id: wf.id,
          name: wf.name,
          is_diverged: false,
          is_new: false,
          is_deleted: true
        }
      end)

    (source_entries ++ deleted_entries)
    |> Enum.sort_by(fn wf -> wf.name end)
  end

  defp resolve_selected_workflow_ids(assigns) do
    all_ids = MapSet.new(assigns.merge_source_workflows, fn wf -> wf.id end)

    if MapSet.equal?(assigns.merge_selected_workflow_ids, all_ids) do
      {nil, nil}
    else
      deleted_ids =
        assigns.merge_source_workflows
        |> Enum.filter(fn wf -> wf.is_deleted end)
        |> MapSet.new(fn wf -> wf.id end)

      selected = assigns.merge_selected_workflow_ids

      selected_source_ids =
        selected
        |> Enum.reject(&MapSet.member?(deleted_ids, &1))
        |> Enum.to_list()

      selected_deleted_ids =
        selected
        |> Enum.filter(&MapSet.member?(deleted_ids, &1))
        |> Enum.to_list()

      {selected_source_ids, selected_deleted_ids}
    end
  end

  defp get_diverged_workflows(source, target_id, workspace_projects) do
    with true <- !is_nil(target_id),
         target_project when not is_nil(target_project) <-
           Enum.find(workspace_projects, &(&1.id == target_id)) do
      MergeProjects.diverged_workflows(source, target_project)
    else
      _ -> []
    end
  end

  defp perform_merge(
         source,
         target,
         actor,
         {selected_workflow_ids, deleted_target_workflow_ids}
       ) do
    maybe_commit_to_github(target, "pre-merge commit")

    opts =
      if selected_workflow_ids do
        %{
          selected_workflow_ids: selected_workflow_ids,
          deleted_target_workflow_ids: deleted_target_workflow_ids
        }
      else
        %{}
      end

    result =
      source
      |> MergeProjects.merge_project(target, opts)
      |> then(
        &Lightning.Projects.Provisioner.import_document(target, actor, &1,
          allow_stale: true
        )
      )

    case result do
      {:ok, _updated_target} = success ->
        Sandboxes.sync_collections(source, target)
        maybe_commit_to_github(target, "Merged sandbox #{source.name}")
        success

      error ->
        error
    end
  end

  defp maybe_commit_to_github(project, commit_message) do
    with %{} = repo_connection <-
           VersionControl.get_repo_connection_for_project(project.id) do
      VersionControl.initiate_sync(repo_connection, commit_message)
    end
  end

  defp handle_merge_result(
         {:ok, _updated_target},
         socket,
         source,
         target,
         _root_project,
         actor
       ) do
    Lightning.Projects.SandboxPromExPlugin.fire_sandbox_merged_event()

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
