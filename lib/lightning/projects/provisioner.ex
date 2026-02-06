defmodule Lightning.Projects.Provisioner do
  @moduledoc """
  Provides functions for importing projects. This module is used by the
  provisioning HTTP API.

  When providing a project to import, all records must have an `id` field.
  It's up to the caller to ensure that the `id` is unique and generated
  ahead of time in the case of new records.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Collections.Collection
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.Services.CollectionHook
  alias Lightning.Services.UsageLimiter
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.VersionControl.VersionControlUsageLimiter
  alias Lightning.Workflows
  alias Lightning.Workflows.Audit
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.KafkaConfiguration
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias Lightning.WorkflowVersions

  @doc """
  Import a project.

  ## Options
    * `:allow_stale` - If true, allows stale operations during import (useful for
      merge operations where concurrent modifications are expected). Defaults to false.
  """
  @spec import_document(
          Project.t() | nil,
          User.t() | ProjectRepoConnection.t(),
          map(),
          keyword()
        ) ::
          {:error,
           Ecto.Changeset.t(Project.t())
           | Lightning.Extensions.UsageLimiting.message()}
          | {:ok, Project.t()}
  def import_document(project, user_or_repo_connection, data, opts \\ [])

  def import_document(nil, %User{} = user, data, opts) do
    import_document(%Project{}, user, data, opts)
  end

  def import_document(project, user_or_repo_connection, data, opts) do
    allow_stale = Keyword.get(opts, :allow_stale, false)

    Repo.transact(fn ->
      with :ok <- VersionControlUsageLimiter.limit_github_sync(project.id),
           project_changeset <-
             build_import_changeset(project, user_or_repo_connection, data),
           edges_to_cleanup <-
             edges_targeting_deleted_jobs(project_changeset),
           {:ok, %{workflows: workflows} = project} <-
             Repo.insert_or_update(project_changeset, allow_stale: allow_stale),
           :ok <- cleanup_orphaned_edges(edges_to_cleanup),
           :ok <- handle_collection_deletion(project_changeset),
           updated_project <- preload_dependencies(project),
           {:ok, _changes} <-
             audit_workflows(project_changeset, user_or_repo_connection),
           {:ok, _changes} <-
             update_workflows_version(
               project_changeset,
               updated_project.workflows
             ),
           {:ok, _changes} <-
             create_snapshots(
               project_changeset,
               updated_project.workflows,
               user_or_repo_connection
             ) do
        Enum.each(workflows, &Workflows.Events.workflow_updated/1)

        project_changeset
        |> get_assoc(:workflows)
        |> Enum.each(&Workflows.publish_kafka_trigger_events/1)

        Lightning.Projects.SandboxPromExPlugin.fire_provisioner_import_event(
          Lightning.Projects.Project.sandbox?(updated_project)
        )

        {:ok, updated_project}
      end
    end)
  end

  defp build_import_changeset(project, user_or_repo_connection, data) do
    project
    |> preload_dependencies()
    |> parse_document(data)
    |> maybe_add_project_user(user_or_repo_connection)
    |> maybe_add_project_credentials(user_or_repo_connection)
  end

  defp audit_workflows(project_changeset, user_or_repo_connection) do
    project_changeset
    |> get_assoc(:workflows)
    |> Enum.reduce(
      Multi.new(),
      fn workflow_changeset, multi ->
        append_audit_multi(workflow_changeset, multi, user_or_repo_connection)
      end
    )
    |> Repo.transaction()
  end

  defp append_audit_multi(workflow_changeset, multi, user_or_repo_connection) do
    case classify_audit(workflow_changeset) do
      {:no_action, _nil} ->
        multi

      {action, workflow_id} ->
        Multi.append(
          multi,
          audit_workflow_multi(action, workflow_id, user_or_repo_connection)
        )
    end
  end

  defp classify_audit(%{action: :insert, changes: %{id: workflow_id}}) do
    {:insert, workflow_id}
  end

  defp classify_audit(%{action: :delete, data: %{id: workflow_id}}) do
    {:delete, workflow_id}
  end

  defp classify_audit(%{
         action: :update,
         data: %{id: workflow_id},
         changes: changes
       })
       when changes != %{} do
    {:update, workflow_id}
  end

  defp classify_audit(_unrecognised_changeset) do
    {:no_action, nil}
  end

  defp update_workflows_version(project_changeset, inserted_workflows) do
    project_changeset
    |> get_assoc(:workflows)
    |> Enum.reject(fn changeset ->
      changeset.changes == %{} or get_change(changeset, :delete)
    end)
    |> Enum.reduce(Multi.new(), fn changeset, multi ->
      workflow =
        Enum.find(inserted_workflows, &(&1.id == get_field(changeset, :id)))

      Multi.run(multi, "version_#{workflow.id}", fn _repo, _changes ->
        hash = WorkflowVersions.generate_hash(workflow)
        WorkflowVersions.record_version(workflow, hash, "cli")
      end)
    end)
    |> Repo.transaction()
    |> normalize_txn()
  end

  defp normalize_txn({:ok, changes}), do: {:ok, changes}
  defp normalize_txn({:error, _key, reason, _}), do: {:error, reason}

  defp audit_workflow_multi(action, workflow_id, user_or_repo_connection) do
    Multi.new()
    |> Multi.insert(
      "audit_#{action}_workflow_#{workflow_id}",
      Audit.provisioner_event(
        action,
        workflow_id,
        user_or_repo_connection
      )
    )
  end

  defp create_snapshots(
         project_changeset,
         inserted_workflows,
         user_or_repo_connection
       ) do
    project_changeset
    |> get_assoc(:workflows)
    |> Enum.reject(fn changeset ->
      changeset.changes == %{} or get_change(changeset, :delete)
    end)
    |> Enum.reduce(Multi.new(), fn changeset, multi ->
      workflow =
        inserted_workflows
        |> Enum.find(fn workflow ->
          workflow.id == get_field(changeset, :id)
        end)

      snapshot_operation = "snapshot_#{workflow.id}"

      Multi.insert(multi, snapshot_operation, Snapshot.build(workflow))
      |> Multi.insert(
        "audit_snapshot_#{workflow.id}",
        fn %{^snapshot_operation => %{id: snapshot_id}} ->
          Audit.snapshot_created(
            workflow.id,
            snapshot_id,
            user_or_repo_connection
          )
        end
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} -> {:ok, changes}
      {:error, _failed_key, changeset, _changes} -> {:error, changeset}
    end
  end

  @spec parse_document(Project.t(), map()) :: Ecto.Changeset.t(Project.t())
  def parse_document(%Project{} = project, data) when is_map(data) do
    project
    |> project_changeset(data)
    |> cast_assoc(:collections, with: &collection_changeset/2)
    |> cast_assoc(:workflows, with: &workflow_changeset/2)
    |> then(fn changeset ->
      case WorkflowUsageLimiter.limit_workflows_activation(
             project,
             get_assoc(changeset, :workflows)
           ) do
        :ok ->
          changeset

        {:error, _reason, %{text: message}} ->
          add_error(changeset, :id, message)
      end
    end)
    |> then(fn changeset ->
      case limit_collection_creation(changeset) do
        :ok ->
          changeset

        {:error, _reason, %{text: message}} ->
          add_error(changeset, :id, message)
      end
    end)
  end

  defp limit_collection_creation(changeset) do
    new_collections_count =
      changeset
      |> get_assoc(:collections)
      |> Enum.count(fn collection_changeset ->
        # We only want to count collections that are being inserted
        collection_changeset.data.__meta__.state == :built
      end)

    if new_collections_count > 0 do
      UsageLimiter.limit_action(
        %Action{type: :new_collection, amount: new_collections_count},
        %Context{project_id: changeset.data.id}
      )
    else
      :ok
    end
  end

  # Before import, find edges whose target_job_id points to a job being deleted.
  # Returns edge IDs so we can clean them up after the FK cascade sets NULL.
  defp edges_targeting_deleted_jobs(project_changeset) do
    deleted_job_ids =
      project_changeset
      |> get_assoc(:workflows)
      |> Enum.flat_map(fn wf_cs ->
        wf_cs
        |> get_assoc(:jobs)
        |> Enum.filter(fn job_cs -> job_cs.action == :delete end)
        |> Enum.map(&get_field(&1, :id))
      end)
      |> Enum.reject(&is_nil/1)

    if deleted_job_ids == [] do
      []
    else
      from(e in Edge,
        where: e.target_job_id in ^deleted_job_ids,
        select: e.id
      )
      |> Repo.all()
    end
  end

  # After import, remove edges that were orphaned by job deletion.
  # Only deletes edges whose IDs we captured before the FK cascade,
  # and only if they still have NULL target_job_id (weren't retargeted).
  defp cleanup_orphaned_edges([]), do: :ok

  defp cleanup_orphaned_edges(edge_ids) do
    from(e in Edge,
      where: e.id in ^edge_ids,
      where: is_nil(e.target_job_id)
    )
    |> Repo.delete_all()

    :ok
  end

  defp handle_collection_deletion(project_changeset) do
    deleted_size =
      project_changeset
      |> get_assoc(:collections)
      |> Enum.reduce(0, fn collection_changeset, sum ->
        if get_change(collection_changeset, :delete) do
          sum + get_field(collection_changeset, :byte_size_sum)
        else
          sum
        end
      end)

    if deleted_size > 0 do
      CollectionHook.handle_delete(
        project_changeset.data.id,
        deleted_size
      )
    else
      :ok
    end
  end

  defp maybe_add_project_user(changeset, user_or_repo_connection) do
    if is_struct(user_or_repo_connection, User) and
         needs_initial_project_user?(changeset) do
      changeset |> add_owner(user_or_repo_connection)
    else
      changeset
    end
  end

  defp needs_initial_project_user?(changeset) do
    changeset
    |> get_field(:project_users)
    |> Enum.empty?()
  end

  defp add_owner(changeset, user) do
    changeset
    |> put_assoc(:project_users, [
      %ProjectUser{user_id: user.id, role: "owner"}
      | changeset |> get_field(:project_users)
    ])
  end

  @doc """
  Preload all dependencies for a project.

  Exclude deleted workflows.
  """
  @spec preload_dependencies(Project.t(), nil | [Ecto.UUID.t(), ...]) ::
          Project.t()
  def preload_dependencies(project, snapshots \\ nil)

  def preload_dependencies(project, nil) do
    w = from(w in Workflow, where: is_nil(w.deleted_at))

    Repo.preload(
      project,
      [
        :project_users,
        :collections,
        project_credentials: [credential: [:user]],
        workflows: {w, [:jobs, :triggers, :edges]}
      ],
      force: true
    )
  end

  def preload_dependencies(project, snapshots) when is_list(snapshots) do
    project = preload_dependencies(project)

    %{project | workflows: Snapshot.get_all_by_ids(snapshots)}
  end

  defp project_changeset(project, attrs) do
    project
    |> cast(attrs, [:id, :name, :description])
    |> validate_required([:id])
    |> validate_extraneous_params()
    |> Project.validate()
  end

  defp collection_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:id, :name, :delete])
    |> validate_required([:id])
    |> maybe_mark_for_deletion()
    |> validate_extraneous_params()
    |> Collection.validate()
  end

  defp workflow_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:id, :name, :delete])
    |> optimistic_lock(:lock_version)
    |> validate_required([:id])
    |> maybe_mark_for_deletion()
    |> validate_extraneous_params()
    |> cast_assoc(:jobs, with: &job_changeset/2)
    |> cast_assoc(:triggers, with: &trigger_changeset/2)
    |> cast_assoc(:edges, with: &edge_changeset/2)
    |> Workflow.validate()
  end

  defp job_changeset(job, attrs) do
    job
    |> Job.changeset(attrs)
    |> cast(attrs, [:delete])
    |> validate_required([:id])
    |> unique_constraint(:id, name: :jobs_pkey)
    |> validate_extraneous_params()
    |> maybe_mark_for_deletion()
  end

  defp trigger_changeset(trigger, attrs) do
    trigger
    |> Trigger.cast_changeset(attrs)
    |> cast_embed(
      :kafka_configuration,
      required: false,
      with: &kafka_config_changeset/2
    )
    |> Trigger.validate()
    |> cast(attrs, [:delete])
    |> validate_required([:id])
    |> unique_constraint(:id, name: :triggers_pkey)
    |> validate_extraneous_params()
    |> maybe_mark_for_deletion()
  end

  defp kafka_config_changeset(kafka_config, attrs) do
    kafka_config
    |> KafkaConfiguration.changeset(attrs)
    |> validate_change(:username, fn :username, _change ->
      [username: "credentials can only be changed through the dashboard"]
    end)
    |> validate_change(:password, fn :password, _change ->
      [password: "credentials can only be changed through the dashboard"]
    end)
  end

  defp edge_changeset(edge, attrs) do
    edge
    |> Edge.changeset(attrs)
    |> cast(attrs, [:delete])
    |> validate_required([:id])
    |> unique_constraint(:id, name: :workflow_edges_pkey)
    |> validate_extraneous_params()
    |> maybe_mark_for_deletion()
  end

  defp maybe_mark_for_deletion(changeset) do
    changeset.changes
    |> Map.pop(:delete)
    |> case do
      {true, others} when map_size(others) == 0 ->
        %{changeset | action: :delete}

      {true, others} when map_size(others) > 0 ->
        changeset
        |> add_error(:delete, "cannot change or add a record while deleting")

      _ ->
        changeset
    end
  end

  defp maybe_add_project_credentials(changeset, user_or_repo_connection) do
    credentials_params = changeset.params["project_credentials"]

    if is_struct(user_or_repo_connection, User) and is_list(credentials_params) do
      user_credentials =
        user_or_repo_connection
        |> Ecto.assoc(:credentials)
        |> Repo.all()

      existing_project_credential_ids =
        Enum.map(changeset.data.project_credentials, fn pc -> pc.id end)

      new_credential_params =
        Enum.filter(credentials_params, fn cred_params ->
          cred_params["id"] not in existing_project_credential_ids and
            cred_params["owner"] == user_or_repo_connection.email
        end)

      new_project_creds_to_add =
        Enum.map(new_credential_params, fn cred_params ->
          credential =
            Enum.find(user_credentials, fn cred ->
              cred.name == cred_params["name"]
            end)

          if credential do
            change(%ProjectCredential{
              id: cred_params["id"],
              credential_id: credential.id
            })
          else
            change(%ProjectCredential{
              id: cred_params["id"]
            })
            |> add_error(
              :credential,
              "No credential found with name #{cred_params["name"]}"
            )
          end
        end)

      project_credentials =
        Enum.map(changeset.data.project_credentials, &change/1)

      put_assoc(
        changeset,
        :project_credentials,
        new_project_creds_to_add ++ project_credentials
      )
    else
      changeset
    end
  end

  @doc """
  Validate that there are no extraneous parameters in the changeset.

  For all params in the changeset, ensure that the param is in the list of
  known fields in the schema.
  """
  def validate_extraneous_params(changeset) do
    param_keys = changeset.params |> Map.keys() |> MapSet.new(&to_string/1)

    field_keys = changeset.types |> Map.keys() |> MapSet.new(&to_string/1)

    extraneous_params = MapSet.difference(param_keys, field_keys)

    if MapSet.size(extraneous_params) > 0 do
      add_error(changeset, :base, "extraneous parameters: %{params}",
        params: MapSet.to_list(extraneous_params) |> Enum.join(", ")
      )
    else
      changeset
    end
  end
end
