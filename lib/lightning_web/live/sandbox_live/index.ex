defmodule LightningWeb.SandboxLive.Index do
  use LightningWeb, :live_view

  alias Ecto.Changeset
  alias Lightning.Helpers
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.MergeProjects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.Sandboxes
  alias Lightning.Repo
  alias Lightning.VersionControl
  alias LightningWeb.SandboxLive.Components

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_menu_item, :sandboxes)
     |> assign(:page_title, "Sandboxes")
     |> assign(
       :limit_new_sandbox,
       ProjectLimiter.limit_new_sandbox(socket.assigns.project.id)
     )
     |> assign(:editing_sandbox, nil)
     |> assign(:new_sandbox_color, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> load_workspace_projects()
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, editing_sandbox: nil, new_sandbox_color: nil)
  end

  defp apply_action(socket, :new, _params) do
    %{project: project, can_create_sandbox: can_create?} = socket.assigns

    case {can_create?, socket.assigns.limit_new_sandbox} do
      {true, :ok} ->
        assign(socket,
          editing_sandbox: nil,
          new_sandbox_color: Components.random_color()
        )

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
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket = assign(socket, new_sandbox_color: nil)

    case find_row(socket, id) do
      nil ->
        socket
        |> assign(:editing_sandbox, nil)
        |> put_flash(:error, "Sandbox not found")

      %{can_edit: true} = sandbox ->
        assign(socket, :editing_sandbox, sandbox)

      _sandbox ->
        socket
        |> assign(:editing_sandbox, nil)
        |> put_flash(:error, "You are not authorized to edit this sandbox")
        |> push_navigate(
          to: ~p"/projects/#{socket.assigns.project.id}/sandboxes"
        )
    end
  end

  # --- Create and edit ---

  # The open form's Save. Which form is open, and whether this user may save
  # it, is the route's and the server's to know, not the payload's.
  @impl true
  def handle_event("create-sandbox", params, socket) do
    %{project: parent, current_user: actor} = socket.assigns

    if socket.assigns.live_action != :new or
         not socket.assigns.can_create_sandbox do
      reply_error(
        socket,
        "You are not authorized to create sandboxes in this workspace"
      )
    else
      changeset = form_changeset(%Project{}, form_params(params), parent.id)

      if changeset.valid? do
        create_sandbox(socket, parent, actor, changeset)
      else
        reply_error(socket, changeset)
      end
    end
  end

  def handle_event("update-sandbox", params, socket) do
    id = params["id"]

    case socket.assigns.editing_sandbox do
      %{id: ^id, can_edit: true} = sandbox ->
        changeset =
          form_changeset(sandbox, form_params(params), sandbox.parent_id)

        if changeset.valid? do
          update_sandbox(socket, sandbox, changeset)
        else
          reply_error(socket, changeset)
        end

      _other ->
        reply_error(socket, "You are not authorized to edit this sandbox")
    end
  end

  # --- Delete and restore ---

  def handle_event(
        "delete-sandbox",
        params,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case find_row(socket, params["id"]) do
      nil ->
        reply_error(socket, "Sandbox not found")

      %{can_delete: true} = sandbox ->
        if params["nameConfirmation"] == sandbox.name do
          sandbox
          |> Sandboxes.schedule_sandbox_deletion(current_user)
          |> handle_sandbox_delete_result(sandbox, socket)
        else
          reply_error(socket, "must match the sandbox name")
        end

      _sandbox ->
        reply_error(socket, "You are not authorized to delete this sandbox")
    end
  end

  def handle_event(
        "cancel-sandbox-deletion",
        params,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case find_row(socket, params["id"]) do
      nil ->
        reply_error(socket, "Sandbox not found")

      %{can_cancel_deletion: true} = sandbox ->
        sandbox
        |> Sandboxes.cancel_scheduled_sandbox_deletion(current_user)
        |> handle_cancel_deletion_result(sandbox, socket)

      _sandbox ->
        reply_error(
          socket,
          "You are not authorized to cancel this sandbox's deletion"
        )
    end
  end

  # --- Merge ---

  # What merging into a target would do. A null target asks for the
  # sandbox's parent, when the viewer may merge into it.
  def handle_event("preview-merge", params, socket) do
    with {:ok, sandbox} <- fetch_mergeable_source(socket, params["id"]) do
      targets = merge_targets(socket, subtree_ids(sandbox))

      case params["targetId"] do
        nil ->
          target = Enum.find(targets, &(&1.id == sandbox.parent_id))
          reply_merge_preview(socket, sandbox, targets, target)

        id ->
          case Enum.find(targets, &(&1.id == id)) do
            nil -> reply_error(socket, "Target project not found")
            target -> reply_merge_preview(socket, sandbox, targets, target)
          end
      end
    end
  end

  def handle_event(
        "merge-sandbox",
        params,
        %{assigns: %{current_user: actor}} = socket
      ) do
    with {:ok, source} <- fetch_mergeable_source(socket, params["id"]),
         {:ok, target} <- fetch_merge_target(socket, source, params["targetId"]) do
      if Permissions.can?(:sandboxes, :merge_sandbox, actor, target) do
        # Keep only the posted ids that this target's preview offers.
        preview = merge_preview(source, target)

        {deleted, carried} = Enum.split_with(preview.workflows, & &1.is_deleted)

        opts = %{
          selected_workflow_ids: picked(params["workflowIds"], carried, & &1.id),
          deleted_target_workflow_ids:
            picked(params["deletedWorkflowIds"], deleted, & &1.id),
          selected_credential_ids:
            picked(params["credentialIds"], preview.credentials, & &1.id),
          skip_collections:
            picked(
              params["skippedCollectionNames"],
              preview.collections_to_add,
              & &1
            )
        }

        source
        |> perform_merge(target, actor, opts)
        |> handle_merge_result(socket, source, target, actor)
      else
        reply_error(socket, "You are not authorized to merge into this project")
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.design_system_page
      name="SandboxesIndexPage"
      props={
        %{
          project: %{
            id: @project.id,
            parentId: @project.parent_id,
            color: @project.color
          },
          projectLabel: @project_label,
          root: sandbox_row_json(@root_project),
          rootIsSandbox: Project.sandbox?(@root_project),
          sandboxes: Enum.map(@sandboxes, &sandbox_row_json/1),
          newHref: ~p"/projects/#{@project}/sandboxes/new",
          createBlockedReason:
            create_sandbox_tooltip_message(
              @can_create_sandbox,
              @limit_new_sandbox,
              @nesting_at_limit
            ),
          gracePeriodDays: Lightning.Config.purge_deleted_after_days(),
          form:
            form_json(
              @live_action,
              @project,
              @editing_sandbox,
              @new_sandbox_color
            )
        }
      }
      banner={assigns[:banner]}
      current_user={@current_user}
    />
    """
  end

  # --- Props ---

  # The shape the design system's SandboxRow type expects.
  defp sandbox_row_json(sandbox) do
    %{
      id: sandbox.id,
      name: sandbox.name,
      color: sandbox.color,
      env: sandbox.env,
      scheduledDeletion: sandbox.scheduled_deletion,
      workflowsHref: ~p"/projects/#{sandbox.id}/w",
      editHref:
        if(Project.sandbox?(sandbox),
          do: ~p"/projects/#{sandbox.parent_id}/sandboxes/#{sandbox.id}/edit"
        ),
      canEdit: sandbox.can_edit,
      canDelete: sandbox.can_delete,
      canMerge: sandbox.can_merge,
      canCancelDeletion: sandbox.can_cancel_deletion,
      restoreBlockedReason: sandbox.restore_blocked_message,
      activeDescendantCount: sandbox.active_descendant_count
    }
  end

  # The design system's SandboxForm while the route has the form open.
  defp form_json(:new, parent, _editing, color) when is_binary(color) do
    %{
      mode: "new",
      parentName: parent.name,
      parentIsSandbox: Project.sandbox?(parent),
      initialColor: color
    }
  end

  defp form_json(:edit, _parent, %{} = sandbox, _color) do
    %{
      mode: "edit",
      sandboxId: sandbox.id,
      initial: %{rawName: sandbox.name, color: sandbox.color}
    }
  end

  defp form_json(_action, _parent, _editing, _color), do: nil

  defp reply_merge_preview(socket, sandbox, targets, target) do
    preview = merge_preview(sandbox, target)

    {:reply,
     %{
       targets: Enum.map(targets, &%{id: &1.id, name: &1.name}),
       targetId: target && target.id,
       workflows: Enum.map(preview.workflows, &merge_workflow_json/1),
       credentials: preview.credentials,
       collectionsToAdd: preview.collections_to_add
     }, socket}
  end

  defp merge_workflow_json(workflow) do
    %{
      id: workflow.id,
      name: workflow.name,
      isChanged: workflow.is_changed,
      isDiverged: workflow.is_diverged,
      isNew: workflow.is_new,
      isDeleted: workflow.is_deleted
    }
  end

  # --- Workspace ---

  defp load_workspace_projects(%{assigns: %{project: project}} = socket) do
    current_user = socket.assigns.current_user
    limit_new_sandbox = socket.assigns.limit_new_sandbox

    access_root = Repo.preload(socket.assigns.access_root, :project_users)

    workspace_root =
      project |> Projects.root_of() |> Repo.preload(:project_users)

    # Every project under the access root, including ones this viewer can't
    # see, so a card counts all the live sandboxes deleting it takes along.
    subtree =
      access_root.id
      |> Projects.list_descendants()
      |> Repo.preload([:parent, :project_users])

    descendants = Projects.visible_sandboxes(subtree, current_user)

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
      Lightning.Policies.Sandboxes.manage_permissions(
        [access_root | descendants],
        current_user,
        workspace_root
      )

    descendant_counts = active_descendant_counts(subtree)

    decorate =
      &decorate_for_render(
        &1,
        manage_permissions,
        limit_new_sandbox,
        Map.get(descendant_counts, &1.id, 0)
      )

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

  # For each project, how many live projects sit anywhere beneath it.
  defp active_descendant_counts(subtree) do
    parent_of = Map.new(subtree, &{&1.id, &1.parent_id})

    subtree
    |> Enum.filter(&is_nil(&1.scheduled_deletion))
    |> Enum.flat_map(&ancestor_ids(parent_of, &1.parent_id))
    |> Enum.frequencies()
  end

  defp ancestor_ids(_parent_of, nil), do: []

  defp ancestor_ids(parent_of, id),
    do: [id | ancestor_ids(parent_of, Map.get(parent_of, id))]

  defp decorate_for_render(
         sandbox,
         manage_permissions,
         limit_new_sandbox,
         active_descendant_count
       ) do
    can_manage? = Map.get(manage_permissions, sandbox.id, false)
    scheduled? = not is_nil(sandbox.scheduled_deletion)

    sandbox
    |> Map.put(:can_edit, can_manage? and not scheduled?)
    |> Map.put(:can_delete, can_manage? and not scheduled?)
    |> Map.put(:can_merge, can_manage? and not scheduled?)
    |> Map.put(:can_cancel_deletion, can_manage? and scheduled?)
    |> Map.put(
      :restore_blocked_message,
      restore_blocked_message(scheduled?, limit_new_sandbox)
    )
    |> Map.put(:active_descendant_count, active_descendant_count)
  end

  defp restore_blocked_message(true, {:error, _reason, %{text: text}}), do: text
  defp restore_blocked_message(_scheduled?, _limit), do: nil

  # Ids come from the browser, so they are looked up in the tree this viewer
  # was shown, never loaded by id.
  defp find_row(socket, id),
    do: Enum.find(socket.assigns.workspace_tree, &(&1.id == id))

  defp create_sandbox_tooltip_message(
         can_create_sandbox,
         limiter_result,
         nesting_at_limit
       ) do
    case {can_create_sandbox, limiter_result, nesting_at_limit} do
      {false, _, _} ->
        "You are not authorized to create sandboxes in this workspace"

      {_, _, true} ->
        nesting_limit_message()

      {_, {:error, _, %{text: text}}, _} ->
        text

      _other ->
        nil
    end
  end

  defp nesting_limit_message do
    "Maximum sandbox nesting depth reached (#{Lightning.Config.max_sandbox_nesting_depth()} levels deep)"
  end

  # --- Create and edit ---

  # Only the form's two fields reach the changeset.
  defp form_params(params) do
    %{"raw_name" => params["rawName"], "color" => params["color"]}
  end

  defp form_changeset(base, params, parent_id) do
    base
    |> Project.form_changeset(params)
    |> validate_unique_sandbox_name(parent_id)
    |> name_errors_on_raw_name()
  end

  # The form has no `name` field, so its errors move onto Name (`raw_name`);
  # a key the form doesn't have would also show "Please fix the errors below."
  defp name_errors_on_raw_name(changeset) do
    changeset = Helpers.copy_error(changeset, :name, :raw_name)
    %{changeset | errors: Keyword.delete(changeset.errors, :name)}
  end

  defp validate_unique_sandbox_name(changeset, parent_id) do
    name = Changeset.get_field(changeset, :name)
    id = Changeset.get_field(changeset, :id)

    if parent_id && name && Projects.sandbox_name_exists?(parent_id, name, id) do
      Changeset.add_error(changeset, :name, "Sandbox name already exists")
    else
      changeset
    end
  end

  defp sandbox_attrs(changeset) do
    %{
      name: Changeset.get_field(changeset, :name),
      color: Changeset.get_field(changeset, :color)
    }
  end

  defp create_sandbox(socket, parent, actor, changeset) do
    attrs = changeset |> sandbox_attrs() |> Map.put(:env, "dev")

    with :ok <- ProjectLimiter.limit_new_sandbox(parent.id),
         {:ok, sandbox} <- Projects.provision_sandbox(parent, actor, attrs) do
      socket
      |> put_flash(:info, "Sandbox created")
      |> push_navigate(to: ~p"/projects/#{sandbox.id}/w")
      |> reply_ok()
    else
      {:error, :unauthorized} ->
        reply_error(
          socket,
          "You are not authorized to create sandboxes in this workspace"
        )

      {:error, :nesting_too_deep} ->
        reply_error(socket, nesting_limit_message())

      {:error, _reason, %{text: text}} ->
        reply_error(socket, text)

      {:error, %Changeset{} = error} ->
        # A sibling may have taken the name since the check above.
        rechecked = form_changeset(%Project{}, changeset.params, parent.id)

        if rechecked.errors[:raw_name],
          do: reply_error(socket, rechecked),
          else: creation_failed(socket, parent, error.errors)

      {:error, reason} ->
        creation_failed(socket, parent, reason)
    end
  end

  defp creation_failed(socket, parent, reason) do
    Logger.error(
      "Sandbox creation failed for project #{parent.id}: #{inspect(reason)}"
    )

    reply_error(
      socket,
      "Something went wrong while creating the sandbox. Please check the parent project's settings and try again."
    )
  end

  defp update_sandbox(socket, sandbox, changeset) do
    %{current_user: actor, project: project} = socket.assigns

    case Projects.update_sandbox(sandbox, actor, sandbox_attrs(changeset)) do
      {:ok, _sandbox} ->
        socket
        |> put_flash(:info, "Sandbox updated")
        |> push_patch(to: ~p"/projects/#{project.id}/sandboxes")
        |> reply_ok()

      {:error, %Changeset{} = error} ->
        # A sibling may have taken the name since the check above.
        rechecked =
          form_changeset(sandbox, changeset.params, sandbox.parent_id)

        if rechecked.errors[:raw_name],
          do: reply_error(socket, rechecked),
          else: reply_error(socket, name_errors_on_raw_name(error))

      {:error, :not_found} ->
        reply_error(socket, "Sandbox not found")

      {:error, :unauthorized} ->
        reply_error(socket, "You are not authorized to edit this sandbox")

      {:error, reason} ->
        Logger.error(
          "Sandbox update failed for project #{sandbox.id}: #{inspect(reason)}"
        )

        reply_error(
          socket,
          "Something went wrong while updating the sandbox. Please try again."
        )
    end
  end

  # --- Delete and restore ---

  defp handle_sandbox_delete_result(
         {:ok, _project},
         deleted_sandbox,
         %{assigns: %{project: current_project}} = socket
       ) do
    socket =
      put_flash(
        socket,
        :info,
        "Sandbox #{deleted_sandbox.name} scheduled for deletion."
      )

    if current_project.id in subtree_ids(deleted_sandbox) do
      socket
      |> push_navigate(to: ~p"/projects/#{deleted_sandbox.parent_id}/sandboxes")
      |> reply_ok()
    else
      socket |> load_workspace_projects() |> reply_ok()
    end
  end

  defp handle_sandbox_delete_result({:error, :unauthorized}, _sandbox, socket),
    do: reply_error(socket, "You don't have permission to delete this sandbox")

  defp handle_sandbox_delete_result({:error, :not_found}, _sandbox, socket),
    do: reply_error(socket, "Sandbox not found")

  defp handle_sandbox_delete_result({:error, reason}, sandbox, socket) do
    Logger.error(
      "Sandbox deletion failed for project #{sandbox.id}: #{inspect(reason)}"
    )

    reply_error(
      socket,
      "Couldn't schedule this sandbox for deletion. Please try again."
    )
  end

  defp handle_cancel_deletion_result({:ok, _sandbox}, sandbox, socket) do
    socket
    |> put_flash(:info, "Cancelled deletion of sandbox #{sandbox.name}.")
    |> load_workspace_projects()
    |> reply_ok()
  end

  defp handle_cancel_deletion_result({:error, :unauthorized}, _sandbox, socket),
    do:
      reply_error(
        socket,
        "You are not authorized to cancel this sandbox's deletion"
      )

  defp handle_cancel_deletion_result({:error, :not_found}, _sandbox, socket),
    do: reply_error(socket, "Sandbox not found")

  defp handle_cancel_deletion_result(
         {:error, _reason, %{text: text}},
         _sandbox,
         socket
       ),
       do: reply_error(socket, text)

  # The sandbox and every project under it, including ones the viewer can't see.
  defp subtree_ids(sandbox),
    do: MapSet.new([sandbox.id | Projects.descendant_ids([sandbox.id])])

  # --- Merge ---

  defp fetch_mergeable_source(socket, id) do
    case find_row(socket, id) do
      nil ->
        reply_error(socket, "Sandbox not found")

      %{can_merge: true} = sandbox ->
        {:ok, sandbox}

      _sandbox ->
        reply_error(socket, "You are not authorized to merge this sandbox")
    end
  end

  defp fetch_merge_target(socket, source, target_id) do
    descendant_ids = subtree_ids(source)

    case Enum.find(
           socket.assigns.workspace_projects,
           &(&1.id == target_id and mergeable_target?(&1, descendant_ids))
         ) do
      nil -> reply_error(socket, "Target project not found")
      target -> {:ok, target}
    end
  end

  # Projects the viewer may merge this sandbox into: live, outside its
  # subtree, and where they are an owner, admin or editor.
  defp merge_targets(socket, descendant_ids) do
    current_user = socket.assigns.current_user

    Enum.filter(socket.assigns.workspace_projects, fn project ->
      mergeable_target?(project, descendant_ids) and
        user_role_on_project(project, current_user) in [:owner, :admin, :editor]
    end)
  end

  defp user_role_on_project(project, user) do
    case Enum.find(project.project_users, &(&1.user_id == user.id)) do
      nil -> nil
      pu -> pu.role
    end
  end

  # `descendant_ids` holds the sandbox itself as well as its subtree.
  defp mergeable_target?(project, descendant_ids) do
    is_nil(project.scheduled_deletion) and
      not MapSet.member?(descendant_ids, project.id)
  end

  defp picked(ids, rows, key) when is_list(ids) do
    offered = MapSet.new(rows, key)
    ids |> Enum.filter(&MapSet.member?(offered, &1)) |> Enum.uniq()
  end

  defp picked(_ids, _rows, _key), do: []

  defp merge_preview(source, nil) do
    %{
      workflows: build_merge_workflow_list(source, [], [], nil),
      credentials: [],
      collections_to_add: []
    }
  end

  defp merge_preview(source, target) do
    source = Repo.preload(source, :workflows)
    target = Repo.preload(target, :workflows)

    %{
      workflows:
        build_merge_workflow_list(
          source,
          MergeProjects.diverged_workflows(source, target),
          MergeProjects.diverged_workflows(target, source),
          target
        ),
      credentials: sandbox_only_credentials(source, target),
      collections_to_add: Sandboxes.preview_collections(source, target).to_create
    }
  end

  defp build_merge_workflow_list(source, _diverged, _changed, nil) do
    source
    |> Repo.preload(:workflows)
    |> Map.get(:workflows, [])
    |> Enum.map(fn wf ->
      %{
        id: wf.id,
        name: wf.name,
        is_changed: true,
        is_diverged: false,
        is_new: true,
        is_deleted: false
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp build_merge_workflow_list(
         source,
         diverged_names,
         sandbox_changed_names,
         target_project
       ) do
    target_workflows = target_project.workflows
    target_workflow_names = MapSet.new(target_workflows, & &1.name)
    diverged_set = MapSet.new(diverged_names)
    sandbox_changed_set = MapSet.new(sandbox_changed_names)
    source_workflow_names = MapSet.new(source.workflows, & &1.name)

    source_entries =
      Enum.map(source.workflows, fn wf ->
        is_new = not MapSet.member?(target_workflow_names, wf.name)

        %{
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
      |> Enum.reject(fn wf ->
        MapSet.member?(source_workflow_names, wf.name) or
          workflow_added_after_fork?(wf, source)
      end)
      |> Enum.map(fn wf ->
        %{
          id: wf.id,
          name: wf.name,
          is_changed: false,
          is_diverged: false,
          is_new: false,
          is_deleted: true
        }
      end)

    Enum.sort_by(source_entries ++ deleted_entries, & &1.name)
  end

  defp workflow_added_after_fork?(%{inserted_at: %DateTime{} = wf_inserted}, %{
         inserted_at: %DateTime{} = fork_time
       }) do
    DateTime.compare(wf_inserted, fork_time) == :gt
  end

  defp workflow_added_after_fork?(_workflow, _source), do: false

  # The sandbox's project_credentials whose underlying credential the target
  # does not already have. These would be dropped on merge unless the user
  # chooses to carry them over.
  defp sandbox_only_credentials(source, target) do
    source = Repo.preload(source, project_credentials: [:credential])
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

  defp perform_merge(source, target, actor, opts) do
    maybe_commit_to_github(target, "pre-merge commit")

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

  defp handle_merge_result({:ok, _updated_target}, socket, source, target, actor) do
    Lightning.Projects.SandboxPromExPlugin.fire_sandbox_merged_event()

    socket
    |> put_flash(:info, build_merge_success_message(source, target, actor))
    |> push_navigate(to: ~p"/projects/#{target.id}/w")
    |> reply_ok()
  end

  defp handle_merge_result({:error, reason}, socket, _source, _target, _actor),
    do: reply_error(socket, format_merge_error(reason))

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

  defp format_merge_error(%{text: text}), do: text

  defp format_merge_error(_reason) do
    "Couldn't merge this sandbox. Please try again."
  end

  # The kit's send resolves on this; the flash says what happened.
  defp reply_ok(socket), do: {:reply, %{}, socket}
end
