defmodule LightningWeb.API.SandboxController do
  @moduledoc """
  A project's sandboxes: listing them, creating one under an id the client
  picks, and previewing or making a merge of one into another project.

      GET  /api/projects/:project_id/sandboxes
      PUT  /api/projects/:project_id/sandboxes/:id                 {"name": "staging"}
      POST /api/projects/:project_id/sandboxes/:id/merge_previews  {"target_project_id": "…"}
      POST /api/projects/:project_id/sandboxes/:id/merges          {"workflow_ids": ["…"]}

  The list is open to anyone who may read the project, the service account
  included. Creating and merging are open only to people, since the caller
  becomes the new sandbox's owner and a merge is recorded as theirs.

  A sandbox under `/api/projects/:project_id/` is a direct child of that
  project; any other project's id counts as missing there.
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Extensions.Message
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.Sandboxes
  alias Lightning.Scope
  alias Lightning.Workflows
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Problem
  alias LightningWeb.API.ProjectJSON
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:project_users, :access_project}
       when action == :index

  plug AuthorizeAction,
       {:sandboxes, :provision_sandbox}
       when action == :update

  plug AuthorizeAction,
       {:sandboxes, :merge_sandbox}
       when action in [:merge_preview, :merge]

  @access_project {:project_users, :access_project}
  @provision {:sandboxes, :provision_sandbox}
  @manage_sandbox {:sandboxes, :update_sandbox}

  @create_accepted [:id, :name, :color, :env, :dataclip_ids]
  @create_types %{
    name: :string,
    color: :string,
    env: :string,
    dataclip_ids: {:array, :string}
  }

  @preview_accepted [:target_project_id]
  @merge_accepted [:target_project_id, :workflow_ids]

  @not_copyable {"names a dataclip the project can't copy into a sandbox",
                 code: :not_found}
  @too_deep {"is already as deeply nested as this instance allows",
             code: :not_allowed}
  @not_a_sandbox_workflow {"names no workflow in the sandbox", code: :not_found}

  @doc """
  Lists the project's direct sandboxes, by name, leaving out those scheduled
  for deletion. Paged like `GET /api/projects`, each entry in its shape.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, parent} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @access_project
           ) do
      page = Projects.paginate_sandboxes(parent, Filters.page(params))

      conn
      |> put_view(ProjectJSON)
      |> render("index.json", page: page, conn: conn)
    end
  end

  @doc """
  Creates a sandbox of the project under the path's id, answering 201 with it
  in the shape of `GET /api/projects/:id`. A sandbox of this project that
  already has the id answers 200, unchanged, to a caller who may manage it. An
  id held by any other project is 409 `id_taken`.

  A refused body answers one 422 with every problem in it, before the plan's
  sandbox limit is asked.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    scope = conn.assigns.scope
    body = conn.body_params

    with {:ok, parent} <-
           Target.project(scope, Request.param(conn, "project_id"), @provision),
         {:ok, id} <- Request.id(Request.param(conn, "id")),
         {:ok, target} <- create_target(scope, parent, id),
         {:ok, entries} <- Request.check(body, id, @create_accepted) do
      case target do
        :new ->
          create(conn, parent, id, body, entries)

        sandbox ->
          with :ok <- Errors.refuse(entries), do: render_project(conn, sandbox)
      end
    end
  end

  defp create_target(scope, %Project{id: parent_id}, id) do
    case Projects.get_project(id) do
      nil ->
        {:ok, :new}

      %Project{parent_id: ^parent_id} = sandbox ->
        Target.project(scope, sandbox, @manage_sandbox)

      %Project{} ->
        {:error, :id_taken}
    end
  end

  defp create(conn, parent, id, body, entries) do
    request = cast({%{}, @create_types}, body, Map.keys(@create_types))

    attrs =
      request
      |> apply_changes()
      |> Map.take([:name, :color, :env])
      |> Map.put(:id, id)

    project_changeset =
      Project.changeset(%Project{}, Map.put(attrs, :parent_id, parent.id))

    dataclip_ids = get_field(request, :dataclip_ids) || []

    with :ok <-
           Errors.refuse(
             entries ++
               Errors.from_changeset(request) ++
               Errors.from_changeset(project_changeset) ++
               dataclip_entries(request, parent, dataclip_ids)
           ),
         :ok <- ProjectLimiter.limit_new_sandbox(parent.id) do
      provision(
        conn,
        parent,
        Map.put(attrs, :dataclip_ids, dataclip_ids)
      )
    end
  end

  # A dataclip list of the wrong type is already among the request's entries.
  defp dataclip_entries(request, parent, ids) do
    if Keyword.has_key?(request.errors, :dataclip_ids) or
         Sandboxes.copyable_dataclips?(parent, ids),
       do: [],
       else: [Errors.entry([:dataclip_ids], @not_copyable)]
  end

  defp provision(conn, parent, attrs) do
    case Sandboxes.provision(parent, conn.assigns.current_resource, attrs) do
      {:ok, sandbox} ->
        conn |> put_status(:created) |> render_project(sandbox)

      {:error, :nesting_too_deep} ->
        Errors.refuse([Errors.entry({:path, "project_id"}, @too_deep)])

      # Someone else created it since the lookup. Rerun the request so the
      # caller meets that project.
      {:error, %Ecto.Changeset{} = changeset} ->
        if Request.id_taken?(changeset),
          do: update(conn, conn.params),
          else: {:error, changeset}

      # The parent's role was checked a moment ago, so this is a membership
      # change that landed in between.
      {:error, :unauthorized} ->
        {:error, :forbidden}
    end
  end

  @doc """
  Answers what merging the sandbox into the target would do, writing nothing.
  The target defaults to the sandbox's parent.
  """
  @spec merge_preview(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def merge_preview(conn, _params) do
    body = conn.body_params

    with {:ok, sandbox} <- sandbox(conn),
         :ok <- Request.check_object(body),
         :ok <- Errors.refuse(Request.unknown_keys(body, [], @preview_accepted)),
         {:ok, target} <- merge_target(conn.assigns.scope, sandbox, body) do
      preview = Sandboxes.merge_preview(sandbox, target)

      json(conn, %{
        target_project_id: target.id,
        workflows:
          Enum.map(preview.workflows, fn workflow ->
            workflow
            |> Map.take([
              :name,
              :source_workflow_id,
              :target_workflow_id,
              :change
            ])
            |> Map.put(:diverged, workflow.diverged?)
          end),
        credentials: preview.credentials
      })
    end
  end

  @doc """
  Merges the sandbox's workflows into the target, which defaults to the
  sandbox's parent, answering 201 with the target in the shape of
  `GET /api/projects/:id`. `workflow_ids` limits the merge to those of the
  sandbox's workflows; a workflow only the target has is never deleted.
  """
  @spec merge(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def merge(conn, _params) do
    body = conn.body_params

    with {:ok, sandbox} <- sandbox(conn),
         :ok <- Request.check_object(body),
         {:ok, workflow_ids} <- selected_workflow_ids(sandbox, body),
         {:ok, target} <- merge_target(conn.assigns.scope, sandbox, body) do
      # An explicit selection, and no deletions listed, so the merge never
      # deletes a workflow only the target has.
      opts = %{
        selected_workflow_ids: workflow_ids,
        deleted_target_workflow_ids: []
      }

      case Sandboxes.merge(sandbox, target, conn.assigns.current_resource, opts) do
        {:ok, target} ->
          conn |> put_status(:created) |> render_project(target)

        {:error, %Message{}} ->
          {:error, :exceeds_limit}

        # The merge logged why it failed.
        {:error, :merge_failed} ->
          {:error, Problem.new(:internal)}
      end
    end
  end

  # The sandbox in the path, once the caller may read its parent, then once
  # they may manage the sandbox itself: an owner or admin of it, or of the
  # project at the top of its tree.
  defp sandbox(conn) do
    scope = conn.assigns.scope

    with {:ok, sandbox} <-
           Target.in_project(
             scope,
             Request.param(conn, "project_id"),
             @access_project,
             Request.param(conn, "id"),
             &get_sandbox/2
           ) do
      Target.project(scope, sandbox, @manage_sandbox)
    end
  end

  defp get_sandbox(parent_id, id) do
    case Projects.get_project(id) do
      %Project{parent_id: ^parent_id} = sandbox -> {:ok, sandbox}
      _missing_or_elsewhere -> {:error, :not_found}
    end
  end

  # Unknown keys and a bad `workflow_ids` are reported together. The target is
  # judged after, since it is a reference the caller has to be able to use.
  defp selected_workflow_ids(sandbox, body) do
    unknown = Request.unknown_keys(body, [], @merge_accepted)
    workflows = Workflows.get_workflows_for(sandbox)
    known = MapSet.new(workflows, & &1.id)

    {ids, entries} =
      case Map.fetch(body, "workflow_ids") do
        :error ->
          {Enum.map(workflows, & &1.id), []}

        {:ok, ids} when is_list(ids) ->
          entries =
            for {id, index} <- Enum.with_index(ids),
                not (is_binary(id) and MapSet.member?(known, id)),
                do: Errors.entry([:workflow_ids, index], @not_a_sandbox_workflow)

          {ids, entries}

        {:ok, _not_a_list} ->
          {[], [Errors.entry([:workflow_ids], {"is invalid", code: :type})]}
      end

    with :ok <- Errors.refuse(unknown ++ entries), do: {:ok, ids}
  end

  # The target named in the body, or the sandbox's parent. One the caller
  # can't see, may not merge into, that is being deleted, or that is the
  # sandbox or one of its own sandboxes, is a 422 entry at the key.
  defp merge_target(scope, sandbox, body) do
    param =
      case Map.get(body, "target_project_id") do
        nil -> {["target_project_id"], sandbox.parent_id}
        value -> {["target_project_id"], value}
      end

    with {:ok, target_id} <- Request.id(param),
         {:ok, target} <- permitted_target(scope, target_id) do
      if Sandboxes.mergeable_target?(sandbox, target),
        do: {:ok, target},
        else:
          refuse_target(
            {"is the sandbox or one of its sandboxes", code: :not_allowed}
          )
    end
  end

  defp permitted_target(scope, target_id) do
    with {:ok, target_scope} <- fetch_target(scope, target_id) do
      case Permissions.permit(
             :sandboxes,
             :merge_sandbox,
             target_scope,
             target_scope.project
           ) do
        :ok ->
          {:ok, target_scope.project}

        {:error, :no_standing} ->
          refuse_target(Errors.not_visible())

        {:error, :scheduled_for_deletion} ->
          refuse_target({"is scheduled for deletion", code: :deleting})

        {:error, :forbidden} ->
          refuse_target(
            {"is a project you may not merge into", code: :no_access}
          )
      end
    end
  end

  defp fetch_target(scope, target_id) do
    case Scope.fetch(scope, target_id) do
      {:ok, target_scope} -> {:ok, target_scope}
      {:error, _unknown} -> refuse_target(Errors.not_visible())
    end
  end

  defp refuse_target(error),
    do: Errors.refuse([Errors.entry([:target_project_id], error)])

  defp render_project(conn, project) do
    conn
    |> put_view(ProjectJSON)
    |> render("show.json",
      project: Projects.get_project_with_users!(project.id),
      conn: conn
    )
  end
end
