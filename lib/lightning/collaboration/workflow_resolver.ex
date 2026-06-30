defmodule Lightning.Collaboration.WorkflowResolver do
  @moduledoc """
  Single authority for resolving "given a `workflow_id` and an `action`, what
  `%Workflow{}` should a collaboration session edit, and in which Ecto state?".

  Both the channel join and the session save delegate here so they cannot
  disagree on whether an id maps to a `:built` or `:loaded` struct — the
  structural root cause behind the `workflows_pkey` duplicate INSERT on collab
  reconnect (#4830).

  The resolver performs **no** authorization (`Permissions.can` stays at the
  channel). It does enforce project-ownership, but only when a `:project` opt is
  supplied, because ownership is a property of the resolved row, not of the
  user.
  """

  import Ecto.Query

  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.WebhookAuthMethod
  alias Lightning.Workflows.Workflow

  @type action :: :new | :edit
  @type resolve_opts :: [
          version: non_neg_integer() | nil,
          project: Project.t() | nil
        ]

  @doc """
  Resolves the `%Workflow{}` a collaboration session should edit.

  Returns `{:ok, workflow, kind}` where `workflow` is already in the correct
  Ecto state (with `jobs`, `edges`, and `triggers` populated and the
  `has_auth_method` flag set on each trigger) and `kind` is the newness
  discriminant (see `t:kind/0`).

  Cases:

    * `action: :new`, no existing row — a freshly built `%Workflow{}` keyed on
      `workflow_id`, with `project_id` from the supplied project, empty
      jobs/edges/triggers, and `lock_version: 0`. Ecto state `:built`, kind
      `:new`. The first-INSERT case.
    * `action: :new`, row already exists — the persisted workflow loaded with
      jobs/edges/triggers. Ecto state `:loaded`, kind `:existing`. Resolving an
      existing id to its loaded row routes the save to UPDATE rather than a
      duplicate INSERT (#4830).
    * `action: :edit`, no version, row exists — the persisted workflow loaded
      with jobs/edges/triggers and `has_auth_method` set. Ecto state `:loaded`,
      kind `:existing`.
    * `action: :edit`, no version, no row — `{:error, :workflow_not_found}`.
    * unknown action — `{:error, :invalid_action}`.
  """
  @typedoc """
  The discriminant the resolver returns alongside the workflow, so callers
  read newness from the tag rather than re-deriving it from struct shape:

    * `:new`      — `:new` action with no existing DB row (a freshly built
      `:built` struct).
    * `:existing` — a `:new` action for an id that already has a row, or an
      `:edit` action (loaded row).
    * `:version`  — a snapshot version-view (`resolve_version/3`).
  """
  @type kind :: :new | :existing | :version

  @spec resolve(
          workflow_id :: Ecto.UUID.t(),
          action :: action(),
          opts :: resolve_opts()
        ) ::
          {:ok, Workflow.t(), kind()}
          | {:error,
             :workflow_not_found
             | :wrong_project
             | :snapshot_not_found
             | :invalid_action}
  def resolve(workflow_id, action, opts \\ [])

  def resolve(workflow_id, :new, opts) do
    project = Keyword.get(opts, :project)

    case load_workflow(workflow_id) do
      nil ->
        # First-INSERT: a freshly built struct keyed on the supplied id, in Ecto
        # state :built so the save routes to an INSERT. lock_version stays at the
        # schema default of 0.
        workflow = %Workflow{
          id: workflow_id,
          project_id: project && project.id,
          name: "Untitled workflow",
          jobs: [],
          edges: [],
          triggers: []
        }

        tag_kind(check_ownership(workflow, project), :new)

      workflow ->
        # A :new action for an id that already has a row resolves to the loaded
        # row, so the save routes to UPDATE rather than a duplicate INSERT
        # (#4830).
        tag_kind(check_ownership(workflow, project), :existing)
    end
  end

  def resolve(workflow_id, :edit, opts) do
    # A non-nil `version:` opt dispatches to resolve_version/3 for a read-only
    # point-in-time view. The version is already a non_neg_integer; the resolver
    # never parses version strings.
    case Keyword.get(opts, :version) do
      nil ->
        project = Keyword.get(opts, :project)

        case load_workflow(workflow_id) do
          nil -> {:error, :workflow_not_found}
          workflow -> tag_kind(check_ownership(workflow, project), :existing)
        end

      version when is_integer(version) ->
        resolve_version(workflow_id, version, opts)
    end
  end

  def resolve(_workflow_id, _action, _opts) do
    {:error, :invalid_action}
  end

  @doc """
  Hydrates a read-only `%Workflow{}` from a specific snapshot version.

  Dispatched from `resolve/3` when a non-nil `:version` opt is present, and may
  also be called directly. The `version` is a `non_neg_integer()` already parsed
  by the caller — the resolver never parses version strings.

  Returns a `%Workflow{}` in Ecto state `:built` carrying the snapshot's
  `lock_version` and tagged with kind `:version`. A version-view is a read-only
  point-in-time view that is never saved through this path; the `:version` kind
  lets callers distinguish it from a genuinely-new workflow.

  Sets `project_id` from the supplied project and performs **no** ownership
  check, unlike the `:edit` latest path. Performs **no** authorization (auth
  stays at the channel).

  Returns `{:error, :snapshot_not_found}` when no snapshot exists for the
  version.
  """
  @spec resolve_version(
          workflow_id :: Ecto.UUID.t(),
          version :: non_neg_integer(),
          opts :: resolve_opts()
        ) :: {:ok, Workflow.t(), kind()} | {:error, :snapshot_not_found}
  def resolve_version(workflow_id, version, opts \\ []) do
    project = Keyword.get(opts, :project)

    case Snapshot.get_by_version(workflow_id, version) do
      nil ->
        {:error, :snapshot_not_found}

      snapshot ->
        trigger_ids = Enum.map(snapshot.triggers, &Ecto.UUID.dump!(&1.id))

        # Snapshot triggers reference auth methods through the join table
        # directly, so derive has_auth_method from a raw query grouped by
        # trigger_id rather than from the schema preload.
        trigger_auth_methods =
          from(twam in "trigger_webhook_auth_methods",
            where: twam.trigger_id in ^trigger_ids,
            join: wam in WebhookAuthMethod,
            on: twam.webhook_auth_method_id == wam.id,
            where: is_nil(wam.scheduled_deletion),
            select: %{trigger_id: twam.trigger_id, auth_method: wam}
          )
          |> Repo.all()
          |> Enum.group_by(
            &Ecto.UUID.cast!(&1.trigger_id),
            & &1.auth_method
          )

        workflow = %Workflow{
          id: workflow_id,
          project_id: project && project.id,
          name: snapshot.name,
          lock_version: snapshot.lock_version,
          deleted_at: nil,
          jobs: Enum.map(snapshot.jobs, &Map.from_struct/1),
          edges: Enum.map(snapshot.edges, &Map.from_struct/1),
          triggers:
            Enum.map(snapshot.triggers, fn trigger ->
              auth_methods = Map.get(trigger_auth_methods, trigger.id, [])

              trigger
              |> Map.from_struct()
              |> Map.put(:has_auth_method, length(auth_methods) > 0)
            end)
        }

        {:ok, workflow, :version}
    end
  end

  # Loads the latest workflow with jobs/edges/triggers, setting has_auth_method
  # per trigger (triggers preload non-deleted webhook_auth_methods ordered by
  # name). Returns nil if no row exists.
  defp load_workflow(workflow_id) do
    case Workflows.get_workflow(workflow_id,
           include: [
             :jobs,
             :edges,
             triggers:
               from(t in Trigger,
                 preload: [
                   webhook_auth_methods:
                     ^from(wam in WebhookAuthMethod,
                       where: is_nil(wam.scheduled_deletion),
                       order_by: wam.name
                     )
                 ]
               )
           ]
         ) do
      nil ->
        nil

      workflow ->
        %{
          workflow
          | triggers:
              Enum.map(workflow.triggers, fn trigger ->
                %{
                  trigger
                  | has_auth_method:
                      length(trigger.webhook_auth_methods || []) > 0
                }
              end)
        }
    end
  end

  # Attaches the newness discriminant to a successful resolution, passing errors
  # through untouched.
  defp tag_kind({:ok, workflow}, kind), do: {:ok, workflow, kind}
  defp tag_kind({:error, _reason} = error, _kind), do: error

  # Ownership is a property of the resolved row, enforced only when a :project
  # opt is supplied.
  defp check_ownership(workflow, nil), do: {:ok, workflow}

  defp check_ownership(%Workflow{project_id: project_id} = workflow, %Project{
         id: id
       })
       when project_id == id do
    {:ok, workflow}
  end

  defp check_ownership(_workflow, %Project{}) do
    {:error, :wrong_project}
  end
end
