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

  require Logger

  defmodule MergeWorkflow do
    defstruct [
      :id,
      :name,
      :is_changed,
      :is_diverged,
      :is_new,
      :is_deleted
    ]
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
        %{assigns: %{project: project, live_action: live_action}} = socket
      )
      when live_action == :edit do
    case Enum.find(socket.assigns.workspace_tree, &(&1.id == id)) do
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
    case Enum.find(socket.assigns.workspace_tree, &(&1.id == sandbox_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sandbox not found")}

      sandbox ->
        if sandbox.can_delete do
          {:noreply,
           socket
           |> assign(:confirm_delete_open?, true)
           |> assign(:confirm_delete_sandbox, sandbox)
           |> assign(:confirm_delete_descendants, active_descendants(sandbox.id))
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
           Sandboxes.schedule_sandbox_deletion(
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
  def handle_event(
        "cancel-sandbox-deletion",
        %{"id" => sandbox_id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case Enum.find(socket.assigns.workspace_tree, &(&1.id == sandbox_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sandbox not found")}

      sandbox ->
        if sandbox.can_cancel_deletion do
          Sandboxes.cancel_scheduled_sandbox_deletion(sandbox, current_user)
          |> handle_cancel_deletion_result(sandbox, socket)
          |> noreply()
        else
          {:noreply,
           put_flash(
             socket,
             :error,
             "You are not authorized to cancel this sandbox's deletion"
           )}
        end
    end
  end

  @impl true
  def handle_event("open-merge-modal", %{"id" => sandbox_id}, socket) do
    case Enum.find(socket.assigns.workspace_tree, &(&1.id == sandbox_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sandbox not found")}

      sandbox ->
        if sandbox.can_merge do
          target_options = get_merge_target_options(socket, sandbox)

          default_target =
            Enum.find(target_options, &(&1.value == sandbox.parent_id))

          descendants = active_descendants(sandbox.id)

          merge_changeset =
            merge_changeset(%{
              target_id: default_target && default_target.value
            })

          target_id = default_target && default_target.value

          target_project =
            Enum.find(
              socket.assigns.workspace_projects,
              fn project -> project.id == target_id end
            )

          {sandbox, target_project} =
            preload_merge_projects(sandbox, target_project)

          diverged_workflows = get_diverged_workflows(sandbox, target_project)

          sandbox_changed_workflows =
            get_changed_workflows(sandbox, target_project)

          source_workflows =
            build_merge_workflow_list(
              sandbox,
              diverged_workflows,
              sandbox_changed_workflows,
              target_project
            )

          selected_ids =
            source_workflows
            |> Enum.filter(fn wf -> wf.is_changed end)
            |> MapSet.new(fn wf -> wf.id end)

          merge_credentials = sandbox_only_credentials(sandbox, target_project)

          {:noreply,
           socket
           |> assign(:merge_modal_open?, true)
           |> assign(:merge_source_sandbox, sandbox)
           |> assign(:merge_target_options, target_options)
           |> assign(:merge_changeset, merge_changeset)
           |> assign(:merge_descendants, descendants)
           |> assign(:merge_diverged_workflows, diverged_workflows)
           |> assign(:merge_source_workflows, source_workflows)
           |> assign(:merge_selected_workflow_ids, selected_ids)
           |> assign(:merge_credentials, merge_credentials)
           |> assign(
             :merge_selected_credential_ids,
             all_credential_ids(merge_credentials)
           )}
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
    in_list? =
      Enum.any?(socket.assigns.merge_source_workflows, &(&1.id == workflow_id))

    if in_list? do
      selected = socket.assigns.merge_selected_workflow_ids

      new_selected =
        if MapSet.member?(selected, workflow_id) do
          MapSet.delete(selected, workflow_id)
        else
          MapSet.put(selected, workflow_id)
        end

      {:noreply, assign(socket, :merge_selected_workflow_ids, new_selected)}
    else
      {:noreply, socket}
    end
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
  def handle_event("toggle-credential", %{"id" => credential_id}, socket) do
    selected = socket.assigns.merge_selected_credential_ids

    new_selected =
      if MapSet.member?(selected, credential_id) do
        MapSet.delete(selected, credential_id)
      else
        MapSet.put(selected, credential_id)
      end

    {:noreply, assign(socket, :merge_selected_credential_ids, new_selected)}
  end

  @impl true
  def handle_event("toggle-all-credentials", _params, socket) do
    all_ids = MapSet.new(socket.assigns.merge_credentials, fn c -> c.id end)

    new_selected =
      if MapSet.equal?(socket.assigns.merge_selected_credential_ids, all_ids) do
        MapSet.new()
      else
        all_ids
      end

    {:noreply, assign(socket, :merge_selected_credential_ids, new_selected)}
  end

  @impl true
  def handle_event(
        "select-merge-target",
        %{"merge" => %{"target_id" => target_id}},
        socket
      ) do
    merge_changeset = merge_changeset(%{target_id: target_id})

    target_project =
      Enum.find(socket.assigns.workspace_projects, fn project ->
        project.id == target_id
      end)

    {sandbox, target_project} =
      preload_merge_projects(socket.assigns.merge_source_sandbox, target_project)

    diverged_workflows = get_diverged_workflows(sandbox, target_project)

    sandbox_changed_workflows = get_changed_workflows(sandbox, target_project)

    source_workflows =
      if target_project do
        build_merge_workflow_list(
          sandbox,
          diverged_workflows,
          sandbox_changed_workflows,
          target_project
        )
      else
        socket.assigns.merge_source_workflows
      end

    prev_ids =
      MapSet.new(socket.assigns.merge_source_workflows, fn wf -> wf.id end)

    all_ids = MapSet.new(source_workflows, fn wf -> wf.id end)

    added_changed_ids =
      source_workflows
      |> Enum.filter(fn wf ->
        wf.is_changed and not MapSet.member?(prev_ids, wf.id)
      end)
      |> MapSet.new(fn wf -> wf.id end)

    selected_ids =
      socket.assigns.merge_selected_workflow_ids
      |> MapSet.intersection(all_ids)
      |> MapSet.union(added_changed_ids)

    merge_credentials = sandbox_only_credentials(sandbox, target_project)

    # Preserve the user's credential choices across form changes (the checkboxes
    # live in the same form, so toggling one fires this event). Keep selections
    # still in the diff, and default any newly-appeared credential to selected.
    new_credential_ids = all_credential_ids(merge_credentials)
    previously_shown_ids = MapSet.new(socket.assigns.merge_credentials, & &1.id)

    selected_credential_ids =
      socket.assigns.merge_selected_credential_ids
      |> MapSet.intersection(new_credential_ids)
      |> MapSet.union(
        MapSet.difference(new_credential_ids, previously_shown_ids)
      )

    {:noreply,
     socket
     |> assign(:merge_changeset, merge_changeset)
     |> assign(:merge_diverged_workflows, diverged_workflows)
     |> assign(:merge_source_workflows, source_workflows)
     |> assign(:merge_selected_workflow_ids, selected_ids)
     |> assign(:merge_credentials, merge_credentials)
     |> assign(:merge_selected_credential_ids, selected_credential_ids)}
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

              selected_credential_ids =
                MapSet.to_list(socket.assigns.merge_selected_credential_ids)

              source
              |> perform_merge(
                target,
                actor,
                selected_ids,
                selected_credential_ids
              )
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
              <LayoutComponents.breadcrumb_project_picker
                project={@project}
                label={@project_label}
              />
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
          enable_create_button={
            @can_create_sandbox and @limit_new_sandbox == :ok and
              not @nesting_at_limit
          }
          disabled_button_tooltip={
            create_sandbox_tooltip_message(
              @can_create_sandbox,
              @limit_new_sandbox,
              @nesting_at_limit
            )
          }
        />

        <Components.workspace_list
          root_project={@root_project}
          current_project={@project}
          sandboxes={@sandboxes}
          enable_create_button={
            @can_create_sandbox and @limit_new_sandbox == :ok and
              not @nesting_at_limit
          }
          disabled_button_tooltip={
            create_sandbox_tooltip_message(
              @can_create_sandbox,
              @limit_new_sandbox,
              @nesting_at_limit
            )
          }
        />

        <Components.confirm_delete_modal
          :if={@confirm_delete_sandbox}
          open?={@confirm_delete_open?}
          sandbox={@confirm_delete_sandbox}
          changeset={@confirm_changeset}
          root_project={@root_project}
          descendants={@confirm_delete_descendants}
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
          credentials={@merge_credentials}
          selected_credential_ids={@merge_selected_credential_ids}
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
    current_user = socket.assigns.current_user
    limit_new_sandbox = socket.assigns.limit_new_sandbox

    access_root = Repo.preload(socket.assigns.access_root, :project_users)

    workspace_root =
      project |> Projects.root_of() |> Repo.preload(:project_users)

    descendants =
      access_root.id
      |> Projects.list_descendants()
      |> Repo.preload([:parent, :project_users])
      |> Projects.visible_sandboxes(current_user)

    can_create_sandbox =
      Permissions.can?(
        :sandboxes,
        :provision_sandbox,
        current_user,
        project
      )

    nesting_at_limit =
      Projects.depth_of(project.id) >=
        Lightning.Config.max_sandbox_nesting_depth()

    manage_permissions =
      Lightning.Policies.Sandboxes.check_manage_permissions(
        [access_root | descendants],
        current_user,
        workspace_root
      )

    decorate =
      &decorate_for_render(&1, manage_permissions, project, limit_new_sandbox)

    decorated_root = decorate.(access_root)
    decorated_sandboxes = Enum.map(descendants, decorate)

    socket
    |> assign(:workspace_projects, [access_root | descendants])
    |> assign(:workspace_tree, [decorated_root | decorated_sandboxes])
    |> assign(:root_project, decorated_root)
    |> assign(:sandboxes, decorated_sandboxes)
    |> assign(:can_create_sandbox, can_create_sandbox)
    |> assign(:nesting_at_limit, nesting_at_limit)
  end

  defp active_descendants(sandbox_id) do
    sandbox_id
    |> Projects.list_descendants()
    |> Enum.filter(&is_nil(&1.scheduled_deletion))
  end

  defp decorate_for_render(
         sandbox,
         manage_permissions,
         current_project,
         limit_new_sandbox
       ) do
    can_manage? = Map.get(manage_permissions, sandbox.id, false)
    scheduled? = not is_nil(sandbox.scheduled_deletion)

    {restore_blocked_by_limit?, restore_blocked_message} =
      restore_block_state(scheduled?, limit_new_sandbox)

    sandbox
    |> Map.put(:can_edit, can_manage? and not scheduled?)
    |> Map.put(:can_delete, can_manage? and not scheduled?)
    |> Map.put(:can_merge, can_manage? and not scheduled?)
    |> Map.put(:can_cancel_deletion, can_manage? and scheduled?)
    |> Map.put(:restore_blocked_by_limit?, restore_blocked_by_limit?)
    |> Map.put(:restore_blocked_message, restore_blocked_message)
    |> Map.put(:scheduled_for_deletion?, scheduled?)
    |> Map.put(:is_current, current_project.id == sandbox.id)
  end

  defp restore_block_state(true, {:error, _reason, %{text: text}}),
    do: {true, text}

  defp restore_block_state(_scheduled?, _limit), do: {false, nil}

  defp reset_delete_modal_state(socket) do
    socket
    |> assign(:confirm_delete_open?, false)
    |> assign(:confirm_delete_sandbox, nil)
    |> assign(:confirm_delete_descendants, [])
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
    |> assign(:merge_credentials, [])
    |> assign(:merge_selected_credential_ids, MapSet.new())
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
        "Sandbox #{deleted_sandbox.name} scheduled for deletion."
      )
      |> reset_delete_modal_state()

    if should_redirect do
      push_navigate(socket_to_return,
        to: ~p"/projects/#{deleted_sandbox.parent_id}/sandboxes"
      )
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
    |> put_flash(
      :error,
      "Failed to schedule sandbox deletion: #{inspect(reason)}"
    )
    |> assign(:confirm_delete_open?, false)
  end

  defp handle_cancel_deletion_result({:ok, _sandbox}, sandbox, socket) do
    socket
    |> put_flash(
      :info,
      "Cancelled deletion of sandbox #{sandbox.name}."
    )
    |> load_workspace_projects()
  end

  defp handle_cancel_deletion_result({:error, :unauthorized}, _sandbox, socket) do
    put_flash(
      socket,
      :error,
      "You are not authorized to cancel this sandbox's deletion"
    )
  end

  defp handle_cancel_deletion_result({:error, :not_found}, _sandbox, socket) do
    put_flash(socket, :error, "Sandbox not found")
  end

  defp handle_cancel_deletion_result(
         {:error, _reason, %{text: text}},
         _sandbox,
         socket
       ) do
    put_flash(socket, :error, text)
  end

  defp get_merge_target_options(socket, source_sandbox) do
    current_user = socket.assigns.current_user
    root_project = socket.assigns.root_project

    socket.assigns.workspace_projects
    |> Enum.reject(fn potential_target ->
      not is_nil(potential_target.scheduled_deletion) or
        potential_target.id == source_sandbox.id or
        Projects.descendant_of?(potential_target, source_sandbox, root_project)
    end)
    |> Enum.filter(fn project ->
      user_role_on_project(project, current_user) in [:owner, :admin, :editor]
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

  defp find_target_project(workspace_projects, target_id) do
    Enum.find(workspace_projects, fn project -> project.id == target_id end)
  end

  defp build_merge_workflow_list(
         source,
         _diverged_names,
         _sandbox_changed_names,
         nil
       ) do
    source
    |> Repo.preload(:workflows)
    |> Map.get(:workflows, [])
    |> Enum.map(fn wf ->
      %MergeWorkflow{
        id: wf.id,
        name: wf.name,
        is_changed: true,
        is_diverged: false,
        is_new: true,
        is_deleted: false
      }
    end)
    |> Enum.sort_by(fn wf -> wf.name end)
  end

  defp build_merge_workflow_list(
         source,
         diverged_names,
         sandbox_changed_names,
         target_project
       ) do
    target_workflows =
      target_project
      |> Repo.preload(:workflows)
      |> Map.get(:workflows, [])

    target_workflow_names = MapSet.new(target_workflows, fn wf -> wf.name end)

    diverged_set = MapSet.new(diverged_names)
    sandbox_changed_set = MapSet.new(sandbox_changed_names)

    source_workflows =
      source
      |> Repo.preload(:workflows)
      |> Map.get(:workflows, [])

    source_workflow_names = MapSet.new(source_workflows, fn wf -> wf.name end)

    source_entries =
      Enum.map(source_workflows, fn wf ->
        is_new = not MapSet.member?(target_workflow_names, wf.name)

        %MergeWorkflow{
          id: wf.id,
          name: wf.name,
          is_changed: is_new or MapSet.member?(sandbox_changed_set, wf.name),
          is_diverged: MapSet.member?(diverged_set, wf.name),
          is_new: is_new,
          is_deleted: false
        }
      end)

    # Target-only workflows are those in the project but absent from the sandbox.
    # A workflow added to the project after the fork was never in this sandbox,
    # so it is not part of the merge and is dropped from the list entirely. What
    # remains are workflows deleted in the sandbox: they default to unchecked so
    # a merge never silently deletes them, and removal is opt-in.
    deleted_entries =
      target_workflows
      |> Enum.reject(fn wf -> MapSet.member?(source_workflow_names, wf.name) end)
      |> Enum.reject(fn wf -> workflow_added_after_fork?(wf, source) end)
      |> Enum.map(fn wf ->
        %MergeWorkflow{
          id: wf.id,
          name: wf.name,
          is_changed: false,
          is_diverged: false,
          is_new: false,
          is_deleted: true
        }
      end)

    (source_entries ++ deleted_entries)
    |> Enum.sort_by(fn wf -> wf.name end)
  end

  defp workflow_added_after_fork?(%{inserted_at: %DateTime{} = wf_inserted}, %{
         inserted_at: %DateTime{} = fork_time
       }) do
    DateTime.compare(wf_inserted, fork_time) == :gt
  end

  defp workflow_added_after_fork?(_workflow, _source), do: false

  # Always pass an explicit selection so unchecked target-only workflows are
  # kept, not deleted. Only workflows deleted in the sandbox reach this list as
  # target-only, and only the ones the user checks are removed.
  defp resolve_selected_workflow_ids(assigns) do
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

  defp preload_merge_projects(source, nil),
    do: {Repo.preload(source, :workflows), nil}

  defp preload_merge_projects(source, target),
    do: {Repo.preload(source, :workflows), Repo.preload(target, :workflows)}

  # The sandbox's project_credentials whose underlying credential the target
  # does not already have. These would be dropped on merge unless the user
  # chooses to carry them over.
  defp sandbox_only_credentials(_source, nil), do: []

  defp sandbox_only_credentials(source, target) do
    source =
      Repo.preload(source, project_credentials: [:credential])

    target = Repo.preload(target, :project_credentials)

    target_credential_ids =
      MapSet.new(target.project_credentials, & &1.credential_id)

    source.project_credentials
    |> Enum.reject(&MapSet.member?(target_credential_ids, &1.credential_id))
    |> Enum.map(fn pc ->
      %{id: pc.id, name: credential_display_name(pc.credential)}
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp credential_display_name(%{name: name}) when is_binary(name), do: name
  defp credential_display_name(_), do: "Untitled credential"

  defp all_credential_ids(merge_credentials) do
    MapSet.new(merge_credentials, & &1.id)
  end

  defp get_diverged_workflows(_source, nil), do: []

  defp get_diverged_workflows(source, target_project) do
    MergeProjects.diverged_workflows(source, target_project)
  end

  defp get_changed_workflows(_source, nil), do: []

  defp get_changed_workflows(source, target_project) do
    MergeProjects.diverged_workflows(target_project, source)
  end

  defp perform_merge(
         source,
         target,
         actor,
         {selected_workflow_ids, deleted_target_workflow_ids},
         selected_credential_ids
       ) do
    maybe_commit_to_github(target, "pre-merge commit")

    opts = %{
      selected_workflow_ids: selected_workflow_ids,
      deleted_target_workflow_ids: deleted_target_workflow_ids,
      selected_credential_ids: selected_credential_ids
    }

    case Sandboxes.merge(source, target, actor, opts) do
      {:ok, _updated_target} = success ->
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
    case Sandboxes.schedule_sandbox_deletion(source, actor) do
      {:ok, _} ->
        "Successfully merged #{source.name} into #{target.name}. " <>
          "Sandbox scheduled for deletion."

      {:error, _} ->
        "Successfully merged #{source.name} into #{target.name}, " <>
          "but could not schedule the sandbox for deletion."
    end
  end

  defp create_sandbox_tooltip_message(
         can_create_sandbox,
         limiter_result,
         nesting_at_limit
       ) do
    case {can_create_sandbox, limiter_result, nesting_at_limit} do
      {false, _, _} ->
        "You are not authorized to create sandboxes in this workspace"

      {_, _, true} ->
        "Maximum sandbox nesting depth reached (#{Lightning.Config.max_sandbox_nesting_depth()} levels deep)"

      {_, {:error, _, %{text: text}}, _} ->
        text

      _other ->
        nil
    end
  end

  defp format_merge_error(%{text: text}), do: text

  defp format_merge_error(_reason) do
    "Couldn't merge this sandbox. Please try again."
  end
end
