defmodule Lightning.Projects.Sandboxes do
  @moduledoc """
  Manage **sandbox projects** - isolated copies of existing projects for safe experimentation.

  Sandboxes allow developers to test changes, experiment with workflows, and collaborate
  without affecting production projects. They share credentials with their parent but
  maintain separate workflow execution environments.

  ## What gets copied to a sandbox

  * **Project settings**: retention policies, concurrency limits, MFA requirements
  * **Workflow structure**: jobs, triggers (disabled), edges, and node positions
  * **Credentials**: references to parent credentials (no secrets duplicated)
  * **Keychain metadata**: cloned for jobs that use them
  * **Version history**: latest workflow version per workflow
  * **Optional dataclips**: named clips of specific types can be selectively copied

  ## Operations

  * `provision/3` - Create a new sandbox from a parent project
  * `update_sandbox/3` - Update sandbox name, color, or environment
  * `delete_sandbox/2` - Delete a sandbox and all its descendants

  ## Authorization

  * **Provisioning**: Requires `:owner` or `:admin` role on the parent project or superuser
  * **Updates/Deletion**: Requires `:owner` or `:admin` role on the sandbox itself,
                          or `:owner` or `:admin` on the root project, or superuser

  ## Transaction safety

  All operations are performed within database transactions to ensure consistency.
  Failed operations leave no partial state behind.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Workflows
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion

  @typedoc """
  Attributes for creating a new sandbox via `provision/3`.

  ## Required
  * `:name` - Sandbox name (must be unique within the parent project)

  ## Optional
  * `:color` - UI color hex string (e.g. `"#336699"`)
  * `:env` - Environment identifier (e.g. `"staging"`, `"dev"`)
  * `:collaborators` - List of `%{user_id: UUID, role: :admin | :editor | :viewer}`
    Note: `:owner` roles and duplicate users are automatically filtered out
  * `:dataclip_ids` - UUIDs of dataclips to copy (only copies named dataclips
    of types `:global`, `:saved_input`, or `:http_request`)
  """
  @type provision_attrs :: %{
          required(:name) => String.t(),
          optional(:color) => String.t() | nil,
          optional(:env) => String.t() | nil,
          optional(:collaborators) => [
            %{user_id: Ecto.UUID.t(), role: :admin | :editor | :viewer}
          ],
          optional(:dataclip_ids) => [Ecto.UUID.t()]
        }

  @cloned_project_fields ~w(
    allow_support_access concurrency description requires_mfa
    retention_policy history_retention_period dataclip_retention_period
  )a

  @allowed_dataclip_types [:global, :saved_input, :http_request]

  @doc """
  Creates a new sandbox project by cloning from a parent project.

  The creator becomes the sandbox owner, and all workflow triggers are disabled.
  Credentials are shared (not duplicated) between parent and sandbox.

  ## Parameters
  * `parent` - Project to clone from
  * `actor` - User creating the sandbox (needs `:owner` or `:admin` role on parent)
  * `attrs` - Creation attributes (see `t:provision_attrs/0`)

  ## Returns
  * `{:ok, sandbox_project}` - Successfully created sandbox
  * `{:error, :unauthorized}` - Actor lacks permission on parent
  * `{:error, changeset}` - Validation or database error

  ## Example
      {:ok, sandbox} = Sandboxes.provision(parent_project, user, %{
        name: "test-environment",
        color: "#336699",
        collaborators: [%{user_id: other_user.id, role: :editor}]
      })
  """
  @spec provision(Project.t(), User.t(), provision_attrs) ::
          {:ok, Project.t()}
          | {:error, :unauthorized | Ecto.Changeset.t() | term()}
  def provision(%Project{} = parent, %User{} = actor, attrs) do
    Permissions.can?(
      :sandboxes,
      :provision_sandbox,
      actor,
      parent
    )
    |> if do
      create_sandbox_from_parent(parent, actor, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Updates a sandbox project's basic attributes.

  ## Parameters
  * `sandbox` - Sandbox project to update (or sandbox ID as string)
  * `actor` - User performing the update (needs `:owner` or `:admin` role on sandbox)
  * `attrs` - Map with `:name`, `:color`, and/or `:env` keys

  ## Returns
  * `{:ok, updated_sandbox}` - Successfully updated sandbox
  * `{:error, :unauthorized}` - Actor lacks permission on sandbox
  * `{:error, :not_found}` - Sandbox ID not found (when using string ID)
  * `{:error, changeset}` - Validation error

  ## Example
    {:ok, updated} = Sandboxes.update_sandbox(sandbox, user, %{
      name: "new-name",
      color: "#ff6b35"
    })
  """
  @spec update_sandbox(Project.t() | Ecto.UUID.t(), User.t(), map()) ::
          {:ok, Project.t()}
          | {:error, :unauthorized | :not_found | Ecto.Changeset.t()}
  def update_sandbox(%Project{} = sandbox, %User{} = actor, attrs)
      when is_map(attrs) do
    Permissions.can?(
      :sandboxes,
      :update_sandbox,
      actor,
      sandbox
    )
    |> if do
      allowed_attrs = Map.take(attrs, [:name, :color, :env])
      Lightning.Projects.update_project(sandbox, allowed_attrs, actor)
    else
      {:error, :unauthorized}
    end
  end

  def update_sandbox(sandbox_id, %User{} = actor, attrs)
      when is_binary(sandbox_id) and is_map(attrs) do
    case Lightning.Projects.get_project(sandbox_id) do
      %Project{} = sandbox -> update_sandbox(sandbox, actor, attrs)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Deletes a sandbox and all its descendant projects.

  **Warning**: This permanently removes the sandbox and any nested sandboxes
  within it. This action cannot be undone.

  ## Parameters
  * `sandbox` - Sandbox project to delete (or sandbox ID as string)
  * `actor` - User performing the deletion (needs `:owner` or `:admin` role on sandbox)

  ## Returns
  * `{:ok, deleted_sandbox}` - Successfully deleted sandbox and descendants
  * `{:error, :unauthorized}` - Actor lacks permission on sandbox
  * `{:error, :not_found}` - Sandbox ID not found (when using string ID)
  * `{:error, reason}` - Database or other deletion error

  ## Example
      {:ok, deleted} = Sandboxes.delete_sandbox(sandbox, user)
  """
  @spec delete_sandbox(Project.t() | Ecto.UUID.t(), User.t()) ::
          {:ok, Project.t()} | {:error, :unauthorized | :not_found | term()}
  def delete_sandbox(%Project{} = sandbox, %User{} = actor) do
    Permissions.can?(
      :sandboxes,
      :delete_sandbox,
      actor,
      sandbox
    )
    |> if do
      case Lightning.Projects.delete_project(sandbox) do
        {:ok, deleted} ->
          Lightning.Projects.SandboxPromExPlugin.fire_sandbox_deleted_event()
          {:ok, deleted}

        error ->
          error
      end
    else
      {:error, :unauthorized}
    end
  end

  def delete_sandbox(sandbox_id, %User{} = actor) when is_binary(sandbox_id) do
    case Lightning.Projects.get_project(sandbox_id) do
      %Project{} = sandbox -> delete_sandbox(sandbox, actor)
      nil -> {:error, :not_found}
    end
  end

  defp create_sandbox_from_parent(parent, actor, attrs) do
    sandbox_name = Map.fetch!(attrs, :name)
    sandbox_color = Map.get(attrs, :color)
    sandbox_env = Map.get(attrs, :env)
    collaborators = Map.get(attrs, :collaborators, [])

    Repo.transaction(fn ->
      parent_with_data = load_parent_associations(parent)

      sandbox_attrs =
        build_sandbox_project_attributes(
          parent_with_data,
          actor,
          sandbox_name,
          sandbox_color,
          sandbox_env,
          collaborators
        )

      case create_empty_sandbox(parent_with_data, sandbox_attrs) do
        {:ok, sandbox} ->
          sandbox
          |> Repo.preload(:project_users)
          |> clone_credentials_from_parent(parent_with_data)
          |> clone_keychains_from_parent(parent_with_data, actor)
          |> clone_workflows_from_parent(parent_with_data)
          |> finalize_sandbox_setup(parent_with_data, attrs)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, project} ->
        Lightning.Projects.SandboxPromExPlugin.fire_sandbox_created_event()
        {:ok, project}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp load_parent_associations(parent) do
    Repo.preload(parent,
      workflows: [
        jobs: [:project_credential, :keychain_credential],
        triggers: [:webhook_auth_methods],
        edges: []
      ],
      project_credentials: [:credential]
    )
  end

  defp build_sandbox_project_attributes(
         parent,
         actor,
         name,
         color,
         env,
         collaborators
       ) do
    owner_membership = %{user_id: actor.id, role: :owner}

    additional_memberships =
      collaborators
      |> List.wrap()
      |> Enum.reject(&(&1.user_id == actor.id or &1.role == :owner))
      |> Enum.uniq_by(& &1.user_id)

    parent
    |> Map.take(@cloned_project_fields)
    |> Map.merge(%{
      name: name,
      color: color,
      env: env,
      project_users: [owner_membership | additional_memberships]
    })
  end

  defp create_empty_sandbox(parent, attrs) do
    Lightning.Projects.create_sandbox(parent, attrs, false)
  end

  defp clone_credentials_from_parent(sandbox, parent) do
    current_time = DateTime.utc_now() |> DateTime.truncate(:second)

    credential_rows =
      Enum.map(parent.project_credentials, fn parent_credential ->
        %{
          project_id: sandbox.id,
          credential_id: parent_credential.credential_id,
          inserted_at: current_time,
          updated_at: current_time
        }
      end)

    {_, inserted_credentials} =
      Repo.insert_all(ProjectCredential, credential_rows,
        on_conflict: :nothing,
        returning: [:id, :credential_id]
      )

    credential_id_mapping =
      Map.new(inserted_credentials, &{&1.credential_id, &1.id})

    Map.put(sandbox, :credential_id_mapping, credential_id_mapping)
  end

  defp clone_keychains_from_parent(sandbox, parent, actor) do
    used_keychains = collect_keychains_used_by_parent_jobs(parent)

    keychain_id_mapping =
      Enum.reduce(used_keychains, %{}, fn original_keychain, mapping ->
        cloned_keychain =
          create_or_find_keychain_in_sandbox(original_keychain, sandbox, actor)

        Map.put(mapping, original_keychain.id, cloned_keychain.id)
      end)

    Map.put(sandbox, :keychain_id_mapping, keychain_id_mapping)
  end

  defp collect_keychains_used_by_parent_jobs(parent) do
    parent.workflows
    |> Enum.flat_map(& &1.jobs)
    |> Enum.map(& &1.keychain_credential)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp create_or_find_keychain_in_sandbox(original_keychain, sandbox, actor) do
    Repo.get_by(KeychainCredential,
      project_id: sandbox.id,
      name: original_keychain.name
    ) ||
      create_keychain_in_sandbox(original_keychain, sandbox, actor)
  end

  defp create_keychain_in_sandbox(original_keychain, sandbox, actor) do
    %KeychainCredential{}
    |> KeychainCredential.changeset(%{
      name: original_keychain.name,
      path: original_keychain.path,
      default_credential_id: original_keychain.default_credential_id
    })
    |> Ecto.Changeset.put_assoc(:project, sandbox)
    |> Ecto.Changeset.put_assoc(:created_by, actor)
    |> Repo.insert!()
  end

  defp clone_workflows_from_parent(sandbox, parent) do
    workflow_id_mapping = create_sandbox_workflows(parent, sandbox)

    updated_sandbox =
      sandbox
      |> Map.put(:workflow_id_mapping, workflow_id_mapping)

    job_id_mapping =
      clone_jobs_with_updated_references(
        parent,
        updated_sandbox.workflow_id_mapping,
        updated_sandbox.credential_id_mapping,
        updated_sandbox.keychain_id_mapping
      )

    trigger_id_mapping =
      clone_triggers_with_disabled_state(parent, workflow_id_mapping)

    updated_sandbox
    |> Map.put(:job_id_mapping, job_id_mapping)
    |> Map.put(:trigger_id_mapping, trigger_id_mapping)
    |> clone_workflow_edges(parent)
    |> update_node_positions(parent)
  end

  defp create_sandbox_workflows(parent, sandbox) do
    Enum.reduce(parent.workflows, %{}, fn parent_workflow, mapping ->
      {:ok, sandbox_workflow} =
        %Workflow{}
        |> Workflow.changeset(%{
          name: parent_workflow.name,
          project_id: sandbox.id,
          concurrency: parent_workflow.concurrency,
          enable_job_logs: parent_workflow.enable_job_logs,
          positions: %{}
        })
        |> Repo.insert()

      Map.put(mapping, parent_workflow.id, sandbox_workflow.id)
    end)
  end

  defp clone_jobs_with_updated_references(
         parent,
         workflow_id_mapping,
         credential_id_mapping,
         keychain_id_mapping
       ) do
    parent.workflows
    |> Enum.flat_map(
      &clone_jobs_for_workflow(
        &1,
        workflow_id_mapping,
        credential_id_mapping,
        keychain_id_mapping
      )
    )
    |> Map.new()
  end

  defp clone_jobs_for_workflow(
         parent_workflow,
         workflow_id_mapping,
         credential_id_mapping,
         keychain_id_mapping
       ) do
    sandbox_workflow_id = Map.fetch!(workflow_id_mapping, parent_workflow.id)

    Enum.map(parent_workflow.jobs, fn parent_job ->
      sandbox_keychain_id =
        get_sandbox_keychain_id(parent_job, keychain_id_mapping)

      sandbox_credential_id =
        get_sandbox_credential_id(
          parent_job,
          sandbox_keychain_id,
          credential_id_mapping
        )

      sandbox_job =
        parent_job
        |> build_job_attributes(
          sandbox_workflow_id,
          sandbox_credential_id,
          sandbox_keychain_id
        )
        |> create_sandbox_job()

      {parent_job.id, sandbox_job.id}
    end)
  end

  defp clone_triggers_with_disabled_state(parent, workflow_id_mapping) do
    parent.workflows
    |> Enum.flat_map(fn parent_workflow ->
      sandbox_workflow_id = Map.fetch!(workflow_id_mapping, parent_workflow.id)

      Enum.map(parent_workflow.triggers, fn parent_trigger ->
        sandbox_trigger_attrs = %{
          id: Ecto.UUID.generate(),
          workflow_id: sandbox_workflow_id,
          type: parent_trigger.type,
          enabled: false,
          comment: parent_trigger.comment,
          custom_path: parent_trigger.custom_path,
          cron_expression: parent_trigger.cron_expression,
          kafka_configuration: parent_trigger.kafka_configuration
        }

        {:ok, sandbox_trigger} =
          %Trigger{}
          |> Trigger.changeset(sandbox_trigger_attrs)
          |> Repo.insert()

        if parent_trigger.webhook_auth_methods &&
             parent_trigger.webhook_auth_methods != [] do
          sandbox_trigger
          |> Repo.preload(:webhook_auth_methods)
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(
            :webhook_auth_methods,
            parent_trigger.webhook_auth_methods
          )
          |> Repo.update!()
        end

        {parent_trigger.id, sandbox_trigger.id}
      end)
    end)
    |> Map.new()
  end

  defp clone_workflow_edges(sandbox, parent) do
    Enum.each(parent.workflows, fn parent_workflow ->
      sandbox_workflow_id =
        Map.fetch!(sandbox.workflow_id_mapping, parent_workflow.id)

      Enum.each(parent_workflow.edges, fn parent_edge ->
        %Edge{}
        |> Edge.changeset(%{
          id: Ecto.UUID.generate(),
          workflow_id: sandbox_workflow_id,
          condition_type: parent_edge.condition_type,
          condition_expression: parent_edge.condition_expression,
          condition_label: parent_edge.condition_label,
          enabled: parent_edge.enabled,
          source_job_id:
            parent_edge.source_job_id &&
              Map.fetch!(sandbox.job_id_mapping, parent_edge.source_job_id),
          source_trigger_id:
            parent_edge.source_trigger_id &&
              Map.fetch!(
                sandbox.trigger_id_mapping,
                parent_edge.source_trigger_id
              ),
          target_job_id:
            parent_edge.target_job_id &&
              Map.fetch!(sandbox.job_id_mapping, parent_edge.target_job_id)
        })
        |> Repo.insert!()
      end)
    end)

    sandbox
  end

  defp update_node_positions(sandbox, parent) do
    Enum.each(parent.workflows, fn parent_workflow ->
      sandbox_workflow_id =
        Map.fetch!(sandbox.workflow_id_mapping, parent_workflow.id)

      parent_job_ids = Enum.map(parent_workflow.jobs, & &1.id)
      parent_trigger_ids = Enum.map(parent_workflow.triggers, & &1.id)

      combined_id_mapping =
        Map.merge(
          Map.take(sandbox.job_id_mapping, parent_job_ids),
          Map.take(sandbox.trigger_id_mapping, parent_trigger_ids)
        )

      updated_positions =
        remap_node_positions(
          parent_workflow.positions || %{},
          combined_id_mapping
        )

      Repo.get!(Workflow, sandbox_workflow_id)
      |> Ecto.Changeset.change(positions: updated_positions)
      |> Repo.update!()
    end)

    sandbox
  end

  defp finalize_sandbox_setup(sandbox, parent, original_attrs) do
    sandbox
    |> copy_workflow_version_history(sandbox.workflow_id_mapping)
    |> create_initial_workflow_snapshots()
    |> copy_selected_dataclips(parent.id, Map.get(original_attrs, :dataclip_ids))
  end

  defp copy_workflow_version_history(sandbox, workflow_id_mapping) do
    latest_versions =
      from(version in WorkflowVersion,
        where: version.workflow_id in ^Map.keys(workflow_id_mapping),
        distinct: version.workflow_id,
        order_by: [
          asc: version.workflow_id,
          desc: version.inserted_at,
          desc: version.id
        ],
        select: %{
          workflow_id: version.workflow_id,
          hash: version.hash,
          source: version.source
        }
      )
      |> Repo.all()

    Enum.each(latest_versions, fn %{
                                    workflow_id: parent_workflow_id,
                                    hash: version_hash,
                                    source: version_source
                                  } ->
      Repo.insert!(%WorkflowVersion{
        workflow_id: Map.fetch!(workflow_id_mapping, parent_workflow_id),
        hash: version_hash,
        source: version_source
      })
    end)

    sandbox
  end

  defp create_initial_workflow_snapshots(sandbox) do
    sandbox_workflow_ids = Map.values(sandbox.workflow_id_mapping)

    Enum.each(sandbox_workflow_ids, fn workflow_id ->
      Lightning.Workflows.Workflow
      |> Repo.get!(workflow_id)
      |> Workflows.maybe_create_latest_snapshot()
    end)

    sandbox
  end

  defp copy_selected_dataclips(sandbox, _parent_id, nil), do: sandbox
  defp copy_selected_dataclips(sandbox, _parent_id, []), do: sandbox

  defp copy_selected_dataclips(sandbox, parent_id, dataclip_ids)
       when is_list(dataclip_ids) do
    selected_dataclips =
      from(dataclip in Lightning.Invocation.Dataclip,
        where:
          dataclip.project_id == ^parent_id and
            dataclip.id in ^dataclip_ids and
            dataclip.type in ^@allowed_dataclip_types and
            not is_nil(dataclip.name),
        select: %{
          name: dataclip.name,
          body: type(dataclip.body, :map),
          type: dataclip.type
        }
      )
      |> Repo.all()

    Enum.each(selected_dataclips, fn dataclip_attrs ->
      dataclip_attrs
      |> Map.put(:project_id, sandbox.id)
      |> Lightning.Invocation.Dataclip.new()
      |> Repo.insert!()
    end)

    sandbox
  end

  defp get_sandbox_keychain_id(
         %{keychain_credential: %KeychainCredential{id: parent_keychain_id}},
         keychain_id_mapping
       ) do
    Map.get(keychain_id_mapping, parent_keychain_id)
  end

  defp get_sandbox_keychain_id(_job, _keychain_id_mapping), do: nil

  defp get_sandbox_credential_id(
         _job,
         sandbox_keychain_id,
         _credential_id_mapping
       )
       when not is_nil(sandbox_keychain_id) do
    nil
  end

  defp get_sandbox_credential_id(
         %{project_credential: %ProjectCredential{credential_id: credential_id}},
         nil,
         credential_id_mapping
       ) do
    Map.get(credential_id_mapping, credential_id)
  end

  defp get_sandbox_credential_id(
         _job,
         _sandbox_keychain_id,
         _credential_id_mapping
       ),
       do: nil

  defp build_job_attributes(
         parent_job,
         sandbox_workflow_id,
         sandbox_credential_id,
         sandbox_keychain_id
       ) do
    %{
      id: Ecto.UUID.generate(),
      name: parent_job.name,
      body: parent_job.body,
      adaptor: parent_job.adaptor,
      workflow_id: sandbox_workflow_id,
      project_credential_id: sandbox_credential_id,
      keychain_credential_id: sandbox_keychain_id
    }
  end

  defp create_sandbox_job(job_attrs) do
    %Job{} |> Job.changeset(job_attrs) |> Repo.insert!()
  end

  defp remap_node_positions(parent_positions, id_mapping)
       when is_map(parent_positions) do
    parent_positions
    |> Enum.reduce(%{}, fn {parent_node_id, coordinates}, updated_positions ->
      case Map.get(id_mapping, parent_node_id) do
        nil ->
          updated_positions

        sandbox_node_id ->
          Map.put(updated_positions, sandbox_node_id, coordinates)
      end
    end)
    |> case do
      empty_map when map_size(empty_map) == 0 -> nil
      positions_map -> positions_map
    end
  end
end
