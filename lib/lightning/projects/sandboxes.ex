defmodule Lightning.Projects.Sandboxes do
  @moduledoc """
  Provision **sandbox** projects as children of an existing project.

  A sandbox is a full project that:
    * clones core **project settings** from the parent,
    * **references** the same credentials via `project_credentials` (no new credentials are created),
    * clones the **workflow DAG** (workflows, jobs, triggers, edges),
    * **disables all triggers** in the sandbox,
    * **remaps positions** (node coordinates) to the new node IDs,
    * copies the **latest** `WorkflowVersion` per workflow to seed version history,
    * can optionally **copy a subset of named dataclips**,
    * **clones Keychain credentials (metadata only) actually used by parent jobs** and
      rewires sandbox jobs to those cloned keychains, and
    * assigns the **creator as :owner**; any **non-owner collaborators** provided are
      included **at creation time** (duplicate/owner entries are filtered).

  ### Authorization

  The `actor` must be `:owner` or `:admin` on the **parent** project.
  Otherwise `{:error, :unauthorized}` is returned and nothing is created.

  ### Invariants & side effects

  * The sandbox is created in a single DB **transaction**.
  * The creator is added as the owner and any **non-owner collaborators** from
    `:collaborators` are also added at creation time (we ensure exactly one owner).
  * Credentials are **not duplicated**; we create `project_credentials` rows
    that reference the parent’s existing `credentials`.
  * **Keychain credentials are cloned as metadata (name/path/default_credential)** into
    the sandbox project; **no secrets are duplicated**. Because we copy
    `project_credentials` first, the keychain’s `default_credential_id` remains valid
    in the sandbox and passes validation.
  * Trigger rows are cloned but always persisted with `enabled: false`.
  * Positions are remapped by translating old node IDs to new ones; if no valid
    positions remain, we store `nil` (UI → auto-layout).
  * There are **no runs** or dataclips copied by default.

  See the `provision/3` docs below for attribute details and return values.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion

  @typedoc """
  Attributes accepted by `provision/3`.

  * `:name` (**required**) – sandbox name (scoped unique per `parent_id`)
  * `:color` (optional) – UI color string (e.g. `"#336699"`)
  * `:env` (optional) – environment slug for the project (e.g. `"staging"`)
  * `:collaborators` (optional) – list of `%{user_id: Ecto.UUID.t(), role: atom()}`
    to add in addition to the creator (owner). Any `:owner` entries are ignored
    and duplicates by `user_id` are removed.
  * `:dataclip_ids` (optional) – list of dataclip IDs to copy **if** they are:
      * named (`name` not `nil`) **and**
      * of type in `[:global, :saved_input, :http_request]`.
  """
  @type provision_attrs :: %{
          required(:name) => String.t(),
          optional(:color) => String.t() | nil,
          optional(:env) => String.t() | nil,
          optional(:collaborators) => [%{user_id: Ecto.UUID.t(), role: atom()}],
          optional(:dataclip_ids) => [Ecto.UUID.t()]
        }

  @clone_fields ~w(
    allow_support_access concurrency description requires_mfa
    retention_policy history_retention_period dataclip_retention_period
  )a

  @allowed_clip_types [:global, :saved_input, :http_request]

  @doc """
  Provisions a sandbox project under `parent` on behalf of `actor`.

  This function performs the full sandbox provisioning workflow described in the
  module documentation. It returns either the newly created sandbox project or
  an error tuple without side effects outside the transaction.

  ## Parameters

    * `parent` – the parent `%Lightning.Projects.Project{}` to clone from
    * `actor` – the `%Lightning.Accounts.User{}` performing the action; must be
      `:owner` or `:admin` on the **parent**
    * `attrs` – map of attributes (see `t:provision_attrs/0` for details)

  ## Returns

    * `{:ok, %Lightning.Projects.Project{}}` on success
    * `{:error, :unauthorized}` if `actor` lacks permission on `parent`
    * `{:error, Ecto.Changeset.t() | term()}` for validation/DB errors

  ## What gets cloned

    * Project settings: `allow_support_access`, `concurrency`, `description`,
      `requires_mfa`, `retention_policy`, `history_retention_period`,
      `dataclip_retention_period`.
    * Credentials: `project_credentials` rows pointing at the **same**
      underlying credentials (no new `credentials`).
    * **Keychain credentials (metadata)**: only the keychains actually used by
      parent jobs are cloned into the sandbox (`name`, `path`, `default_credential_id`);
      sandbox jobs are rewired to those cloned keychains.
    * DAG: workflows, jobs, triggers (disabled), edges, webhook auth methods.
    * Positions: remapped from parent node IDs to child node IDs; `nil` when
      nothing remaps (UI → auto-layout).
    * Version heads: latest `WorkflowVersion` per workflow (`hash`, `source`).
  """
  @spec provision(Project.t(), User.t(), provision_attrs) ::
          {:ok, Project.t()}
          | {:error, :unauthorized | Ecto.Changeset.t() | term()}
  def provision(%Project{} = parent, %User{} = actor, attrs) do
    case Lightning.Projects.get_project_user_role(actor, parent) do
      role when role in [:owner, :admin] -> do_provision(parent, actor, attrs)
      _ -> {:error, :unauthorized}
    end
  end

  defp do_provision(parent, actor, attrs) do
    name = Map.fetch!(attrs, :name)
    color = Map.get(attrs, :color)
    env = Map.get(attrs, :env)
    collaborators = Map.get(attrs, :collaborators, [])

    Repo.transaction(fn ->
      parent = preload_parent(parent)

      base_attrs =
        build_base_attrs(parent, actor, name, color, env, collaborators)

      case create_sandbox(parent, base_attrs) do
        {:ok, sandbox} ->
          cred_map = copy_credentials!(parent, sandbox)
          kc_map = clone_keychains!(parent, sandbox, actor)
          wf_map = create_workflows!(parent, sandbox)
          job_map = clone_jobs!(parent, wf_map, cred_map, kc_map)
          trg_map = clone_triggers!(parent, wf_map)

          clone_edges!(parent, wf_map, job_map, trg_map)
          remap_positions!(parent, wf_map, job_map, trg_map)
          copy_latest_heads!(wf_map)

          head = Lightning.Projects.compute_project_head_hash(sandbox.id)
          sandbox = Lightning.Projects.append_project_head!(sandbox, head)

          maybe_clone_named_dataclips!(
            parent.id,
            sandbox.id,
            Map.get(attrs, :dataclip_ids)
          )

          sandbox

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
    |> case do
      {:ok, project} -> {:ok, project}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp preload_parent(parent) do
    Repo.preload(parent,
      workflows: [
        jobs: [:project_credential, :keychain_credential],
        triggers: [:webhook_auth_methods],
        edges: []
      ],
      project_credentials: [:credential]
    )
  end

  defp build_base_attrs(parent, actor, name, color, env, collaborators) do
    owner_user = %{user_id: actor.id, role: :owner}

    extras =
      collaborators
      |> List.wrap()
      |> Enum.reject(&(&1.user_id == actor.id or &1.role == :owner))
      |> Enum.uniq_by(& &1.user_id)

    parent
    |> Map.take(@clone_fields)
    |> Map.merge(%{
      name: name,
      color: color,
      env: env,
      project_users: [owner_user | extras]
    })
  end

  defp create_sandbox(parent, attrs) do
    Lightning.Projects.create_sandbox(parent, attrs, false)
  end

  defp copy_credentials!(parent, sandbox) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(parent.project_credentials, fn pc ->
        %{
          project_id: sandbox.id,
          credential_id: pc.credential_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_, returning} =
      Repo.insert_all(ProjectCredential, rows,
        on_conflict: :nothing,
        returning: [:id, :credential_id]
      )

    Map.new(returning, &{&1.credential_id, &1.id})
  end

  # Clone only the keychain credentials that parent jobs actually use.
  # Returns a map of old_keychain_id => new_keychain_id in the sandbox.
  defp clone_keychains!(parent, sandbox, actor) do
    parent
    |> collect_used_keychains()
    |> Enum.reduce(%{}, fn kc, acc ->
      %KeychainCredential{id: new_id} =
        insert_or_get_keychain!(kc, sandbox, actor)

      Map.put(acc, kc.id, new_id)
    end)
  end

  defp collect_used_keychains(parent) do
    parent.workflows
    |> Enum.flat_map(& &1.jobs)
    |> Enum.map(& &1.keychain_credential)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  # Prefer deterministic upsert: check for existing (unique by project_id+name),
  # otherwise insert a fresh keychain tied to the sandbox + actor.
  defp insert_or_get_keychain!(%KeychainCredential{} = kc, sandbox, actor) do
    Repo.get_by(KeychainCredential, project_id: sandbox.id, name: kc.name) ||
      %KeychainCredential{}
      |> KeychainCredential.changeset(%{
        name: kc.name,
        path: kc.path,
        default_credential_id: kc.default_credential_id
      })
      |> Ecto.Changeset.put_assoc(:project, sandbox)
      |> Ecto.Changeset.put_assoc(:created_by, actor)
      |> Repo.insert!()
  end

  defp create_workflows!(parent, sandbox) do
    Enum.reduce(parent.workflows, %{}, fn w, acc ->
      {:ok, new_w} =
        %Workflow{}
        |> Workflow.changeset(%{
          name: w.name,
          project_id: sandbox.id,
          concurrency: w.concurrency,
          enable_job_logs: w.enable_job_logs,
          positions: %{}
        })
        |> Repo.insert()

      Map.put(acc, w.id, new_w.id)
    end)
  end

  # Respects keychain rewiring: if a job used a keychain in the parent,
  # we set keychain_credential_id and keep project_credential_id nil;
  # otherwise we map the static project_credential as before.
  defp clone_jobs!(parent, wf_map, cred_map, kc_map) do
    parent.workflows
    |> Enum.flat_map(&clone_jobs_for_workflow(&1, wf_map, cred_map, kc_map))
    |> Map.new()
  end

  defp clone_jobs_for_workflow(w, wf_map, cred_map, kc_map) do
    new_wf_id = Map.fetch!(wf_map, w.id)

    Enum.map(w.jobs, fn j ->
      child_kc_id = child_keychain_id(j, kc_map)
      child_pc_id = project_credential_id_for_clone(j, child_kc_id, cred_map)

      new_job =
        j
        |> build_job_attrs(new_wf_id, child_pc_id, child_kc_id)
        |> insert_job!()

      {j.id, new_job.id}
    end)
  end

  defp clone_triggers!(parent, wf_map) do
    parent.workflows
    |> Enum.flat_map(fn w ->
      new_wf_id = Map.fetch!(wf_map, w.id)

      Enum.map(w.triggers, fn t ->
        attrs = %{
          id: Ecto.UUID.generate(),
          workflow_id: new_wf_id,
          type: t.type,
          enabled: false,
          comment: t.comment,
          custom_path: t.custom_path,
          cron_expression: t.cron_expression,
          kafka_configuration: t.kafka_configuration
        }

        {:ok, new_t} = %Trigger{} |> Trigger.changeset(attrs) |> Repo.insert()

        if t.webhook_auth_methods && t.webhook_auth_methods != [] do
          new_t
          |> Repo.preload(:webhook_auth_methods)
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(
            :webhook_auth_methods,
            t.webhook_auth_methods
          )
          |> Repo.update!()
        end

        {t.id, new_t.id}
      end)
    end)
    |> Map.new()
  end

  defp clone_edges!(parent, wf_map, job_map, trg_map) do
    Enum.each(parent.workflows, fn w ->
      new_wf_id = Map.fetch!(wf_map, w.id)

      Enum.each(w.edges, fn e ->
        %Edge{}
        |> Edge.changeset(%{
          id: Ecto.UUID.generate(),
          workflow_id: new_wf_id,
          condition_type: e.condition_type,
          condition_expression: e.condition_expression,
          condition_label: e.condition_label,
          enabled: e.enabled,
          source_job_id: e.source_job_id && Map.fetch!(job_map, e.source_job_id),
          source_trigger_id:
            e.source_trigger_id && Map.fetch!(trg_map, e.source_trigger_id),
          target_job_id: e.target_job_id && Map.fetch!(job_map, e.target_job_id)
        })
        |> Repo.insert!()
      end)
    end)
  end

  defp child_keychain_id(
         %{keychain_credential: %KeychainCredential{id: old_id}},
         kc_map
       ),
       do: Map.get(kc_map, old_id)

  defp child_keychain_id(_job, _kc_map), do: nil

  defp project_credential_id_for_clone(_job, child_kc_id, _cred_map)
       when not is_nil(child_kc_id),
       do: nil

  defp project_credential_id_for_clone(
         %{project_credential: %ProjectCredential{credential_id: cred_id}},
         nil,
         cred_map
       ),
       do: Map.get(cred_map, cred_id)

  defp project_credential_id_for_clone(_job, _child_kc_id, _cred_map), do: nil

  defp build_job_attrs(j, new_wf_id, child_pc_id, child_kc_id) do
    %{
      id: Ecto.UUID.generate(),
      name: j.name,
      body: j.body,
      adaptor: j.adaptor,
      workflow_id: new_wf_id,
      project_credential_id: child_pc_id,
      keychain_credential_id: child_kc_id
    }
  end

  defp insert_job!(attrs),
    do: %Job{} |> Job.changeset(attrs) |> Repo.insert!()

  defp remap_positions!(parent, wf_map, job_map, trg_map) do
    Enum.each(parent.workflows, fn w ->
      new_wf_id = Map.fetch!(wf_map, w.id)

      wf_job_ids = Enum.map(w.jobs, & &1.id)
      wf_trg_ids = Enum.map(w.triggers, & &1.id)

      id_map =
        Map.merge(
          Map.take(job_map, wf_job_ids),
          Map.take(trg_map, wf_trg_ids)
        )

      new_positions = remap_positions(w.positions || %{}, id_map)

      Repo.get!(Workflow, new_wf_id)
      |> Ecto.Changeset.change(positions: new_positions)
      |> Repo.update!()
    end)
  end

  defp copy_latest_heads!(wf_map) do
    latest =
      from(v in WorkflowVersion,
        where: v.workflow_id in ^Map.keys(wf_map),
        distinct: v.workflow_id,
        order_by: [asc: v.workflow_id, desc: v.inserted_at, desc: v.id],
        select: %{workflow_id: v.workflow_id, hash: v.hash, source: v.source}
      )
      |> Repo.all()

    Enum.each(latest, fn %{workflow_id: old_id, hash: h, source: s} ->
      Repo.insert!(%WorkflowVersion{
        workflow_id: Map.fetch!(wf_map, old_id),
        hash: h,
        source: s
      })
    end)
  end

  defp maybe_clone_named_dataclips!(_parent_id, _sandbox_id, nil), do: :ok
  defp maybe_clone_named_dataclips!(_parent_id, _sandbox_id, []), do: :ok

  defp maybe_clone_named_dataclips!(parent_id, sandbox_id, dataclip_ids)
       when is_list(dataclip_ids) do
    clips =
      from(d in Lightning.Invocation.Dataclip,
        where:
          d.project_id == ^parent_id and
            d.id in ^dataclip_ids and
            d.type in ^@allowed_clip_types and
            not is_nil(d.name),
        select: %{name: d.name, body: d.body, type: d.type}
      )
      |> Repo.all()

    Enum.each(clips, fn attrs ->
      attrs
      |> Map.put(:project_id, sandbox_id)
      |> Lightning.Invocation.Dataclip.new()
      |> Repo.insert!()
    end)
  end

  defp remap_positions(pos_map, id_map) when is_map(pos_map) do
    pos_map
    |> Enum.reduce(%{}, fn {old_id, coords}, acc ->
      case Map.get(id_map, old_id) do
        nil -> acc
        new_id -> Map.put(acc, new_id, coords)
      end
    end)
    |> case do
      m when map_size(m) == 0 -> nil
      m -> m
    end
  end
end
