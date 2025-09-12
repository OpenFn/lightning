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

  @doc """
  Merges a sandbox workflow back onto its parent workflow.

  This function matches nodes between source and target workflows using:
  1. Structural position in the DAG (primary criterion)
  2. Name and/or adaptor for disambiguation when structure is ambiguous

  Returns params compatible with `Provisioner.import_document`.

  ## Parameters
    * `source_workflow` - The sandbox workflow with modifications
    * `target_workflow` - The parent workflow to merge changes onto

  ## Returns
    A map with the merged workflow structure ready for import:
    * Matched nodes keep target UUIDs with source properties
    * Unmatched source nodes get new UUIDs
    * Unmatched target nodes are marked for deletion
    * Edges are remapped to final node IDs
  """
  @spec merge_workflow(Workflow.t(), Workflow.t()) :: map()
  def merge_workflow(
        %Workflow{} = source_workflow,
        %Workflow{} = target_workflow
      ) do
    source_workflow = preload_workflow(source_workflow)
    target_workflow = preload_workflow(target_workflow)

    # Build DAG structures for both workflows
    source_dag = build_dag_structure(source_workflow)
    target_dag = build_dag_structure(target_workflow)

    # Match nodes between source and target
    {job_matches, trigger_matches} = match_nodes(source_dag, target_dag)

    # Build merged jobs
    merged_jobs =
      build_merged_jobs(
        source_workflow.jobs,
        target_workflow.jobs,
        job_matches
      )

    # Build merged triggers (webhook and cron only)
    merged_triggers =
      build_merged_triggers(
        source_workflow.triggers,
        target_workflow.triggers,
        trigger_matches
      )

    # Build ID mapping for edge remapping
    id_map = build_id_map(job_matches, trigger_matches)

    # Remap edges using the ID mapping
    merged_edges = build_merged_edges(source_workflow.edges, id_map)

    %{
      "id" => target_workflow.id,
      "name" => source_workflow.name,
      "jobs" => merged_jobs,
      "triggers" => merged_triggers,
      "edges" => merged_edges
    }
  end

  defp preload_workflow(workflow) do
    Repo.preload(workflow, [:jobs, :triggers, :edges], force: true)
  end

  defp build_dag_structure(workflow) do
    # Build adjacency lists for structural analysis
    edges_by_source =
      workflow.edges
      |> Enum.group_by(fn edge ->
        cond do
          edge.source_trigger_id -> {:trigger, edge.source_trigger_id}
          edge.source_job_id -> {:job, edge.source_job_id}
          true -> nil
        end
      end)
      |> Map.reject(fn {k, _} -> is_nil(k) end)

    edges_by_target =
      workflow.edges
      |> Enum.group_by(fn edge ->
        if edge.target_job_id, do: {:job, edge.target_job_id}, else: nil
      end)
      |> Map.reject(fn {k, _} -> is_nil(k) end)

    jobs_map = Map.new(workflow.jobs, &{&1.id, &1})
    triggers_map = Map.new(workflow.triggers, &{&1.id, &1})

    %{
      jobs: jobs_map,
      triggers: triggers_map,
      edges_by_source: edges_by_source,
      edges_by_target: edges_by_target,
      edges: workflow.edges
    }
  end

  defp match_nodes(source_dag, target_dag) do
    # Match triggers first (simpler: only webhook and cron)
    trigger_matches = match_triggers(source_dag.triggers, target_dag.triggers)

    # Match jobs using structural position and disambiguation
    job_matches =
      match_jobs_structurally(source_dag, target_dag, trigger_matches)

    {job_matches, trigger_matches}
  end

  defp match_triggers(source_triggers, target_triggers) do
    # Only handle webhook and cron triggers
    source_list =
      source_triggers
      |> Map.values()
      |> Enum.filter(&(&1.type in [:webhook, :cron]))

    target_list =
      target_triggers
      |> Map.values()
      |> Enum.filter(&(&1.type in [:webhook, :cron]))

    # Try to match by type and structural position
    Enum.reduce(source_list, %{}, fn source_trigger, acc ->
      # Find candidates with same type
      candidates = Enum.filter(target_list, &(&1.type == source_trigger.type))

      matched_target =
        case candidates do
          [single] ->
            single

          multiple when length(multiple) > 1 ->
            # Try to disambiguate using cron_expression for cron triggers
            if source_trigger.type == :cron do
              Enum.find(
                multiple,
                &(&1.cron_expression == source_trigger.cron_expression)
              )
            else
              nil
            end

          _ ->
            nil
        end

      if matched_target do
        Map.put(acc, source_trigger.id, matched_target.id)
      else
        # New trigger - generate new ID
        Map.put(acc, source_trigger.id, Ecto.UUID.generate())
      end
    end)
  end

  defp match_jobs_structurally(source_dag, target_dag, trigger_matches) do
    source_jobs = Map.values(source_dag.jobs)
    target_jobs = Map.values(target_dag.jobs)

    # Build structural signatures for all jobs
    source_signatures =
      build_job_signatures(source_jobs, source_dag, trigger_matches)

    target_signatures = build_job_signatures(target_jobs, target_dag, %{})

    # Match jobs based on structural position
    Enum.reduce(source_jobs, %{}, fn source_job, acc ->
      source_sig = Map.get(source_signatures, source_job.id)

      # Find target jobs with matching structural signature
      candidates =
        target_jobs
        |> Enum.filter(fn target_job ->
          target_sig = Map.get(target_signatures, target_job.id)
          signatures_match?(source_sig, target_sig, trigger_matches)
        end)
        |> Enum.reject(fn target_job ->
          # Don't match already matched targets
          Map.values(acc) |> Enum.member?(target_job.id)
        end)

      matched_target =
        case candidates do
          [] ->
            nil

          [single] ->
            single

          multiple ->
            # Disambiguate using name and/or adaptor
            disambiguate_jobs(source_job, multiple)
        end

      if matched_target do
        Map.put(acc, source_job.id, matched_target.id)
      else
        # New job - generate new ID
        Map.put(acc, source_job.id, Ecto.UUID.generate())
      end
    end)
  end

  defp build_job_signatures(jobs, dag, id_map) do
    Map.new(jobs, fn job ->
      parents = get_parent_nodes(job.id, dag)
      children = get_child_nodes(job.id, dag)

      # Map parent/child IDs if needed
      mapped_parents = map_node_refs(parents, id_map)
      mapped_children = map_node_refs(children, id_map)

      signature = %{
        parents: mapped_parents |> Enum.sort(),
        children: mapped_children |> Enum.sort(),
        parent_count: length(mapped_parents),
        child_count: length(mapped_children)
      }

      {job.id, signature}
    end)
  end

  defp get_parent_nodes(job_id, dag) do
    dag.edges_by_target
    |> Map.get({:job, job_id}, [])
    |> Enum.map(fn edge ->
      cond do
        edge.source_trigger_id -> {:trigger, edge.source_trigger_id}
        edge.source_job_id -> {:job, edge.source_job_id}
        true -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_child_nodes(job_id, dag) do
    dag.edges_by_source
    |> Map.get({:job, job_id}, [])
    |> Enum.map(fn edge ->
      if edge.target_job_id, do: {:job, edge.target_job_id}, else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp map_node_refs(node_refs, id_map) do
    Enum.map(node_refs, fn {type, id} ->
      mapped_id = Map.get(id_map, id, id)
      {type, mapped_id}
    end)
  end

  defp signatures_match?(source_sig, target_sig, trigger_matches) do
    # Check if structural positions match
    # Parent and child counts must match
    # Check if parent sets match (accounting for trigger mapping)
    # Children matching is more complex - we check count for now
    source_sig.parent_count == target_sig.parent_count &&
      source_sig.child_count == target_sig.child_count &&
      parents_match?(source_sig.parents, target_sig.parents, trigger_matches) &&
      length(source_sig.children) == length(target_sig.children)
  end

  defp parents_match?(source_parents, target_parents, trigger_matches) do
    # Map source trigger parents using trigger_matches
    mapped_source_parents =
      Enum.map(source_parents, fn
        {:trigger, id} -> {:trigger, Map.get(trigger_matches, id, id)}
        other -> other
      end)

    # For now, check if counts match - more sophisticated matching could be added
    length(mapped_source_parents) == length(target_parents)
  end

  defp disambiguate_jobs(source_job, candidates) do
    # First try exact name match
    by_name = Enum.find(candidates, &(&1.name == source_job.name))

    if by_name do
      by_name
    else
      # Try adaptor match
      by_adaptor = Enum.find(candidates, &(&1.adaptor == source_job.adaptor))

      if by_adaptor do
        by_adaptor
      else
        # Can't disambiguate - no match
        nil
      end
    end
  end

  defp build_merged_jobs(source_jobs, target_jobs, job_matches) do
    source_job_map = Map.new(source_jobs, &{&1.id, &1})
    target_job_map = Map.new(target_jobs, &{&1.id, &1})

    # Get all matched target IDs
    matched_target_ids = Map.values(job_matches) |> MapSet.new()

    # Process source jobs (matched and new)
    merged_from_source =
      Enum.map(job_matches, fn {source_id, target_id} ->
        source_job = Map.get(source_job_map, source_id)
        target_job = Map.get(target_job_map, target_id)

        if target_job do
          # Matched job - use target ID, source properties, preserve credentials
          %{
            "id" => target_id,
            "name" => source_job.name,
            "body" => source_job.body,
            "adaptor" => source_job.adaptor,
            "project_credential_id" => target_job.project_credential_id,
            "keychain_credential_id" => target_job.keychain_credential_id
          }
        else
          # New job - source with new ID
          %{
            # This is actually a new UUID from job_matches
            "id" => target_id,
            "name" => source_job.name,
            "body" => source_job.body,
            "adaptor" => source_job.adaptor,
            "project_credential_id" => source_job.project_credential_id,
            "keychain_credential_id" => source_job.keychain_credential_id
          }
        end
      end)

    # Mark unmatched target jobs for deletion
    deleted_targets =
      target_jobs
      |> Enum.filter(fn job ->
        not MapSet.member?(matched_target_ids, job.id)
      end)
      |> Enum.map(fn job ->
        %{
          "id" => job.id,
          "delete" => true
        }
      end)

    merged_from_source ++ deleted_targets
  end

  defp build_merged_triggers(source_triggers, target_triggers, trigger_matches) do
    # Only handle webhook and cron triggers
    source_triggers =
      Enum.filter(source_triggers, &(&1.type in [:webhook, :cron]))

    target_triggers =
      Enum.filter(target_triggers, &(&1.type in [:webhook, :cron]))

    source_trigger_map = Map.new(source_triggers, &{&1.id, &1})

    matched_target_ids = Map.values(trigger_matches) |> MapSet.new()

    # Process source triggers (matched and new)
    merged_from_source =
      Enum.map(trigger_matches, fn {source_id, target_id} ->
        source_trigger = Map.get(source_trigger_map, source_id)

        if source_trigger do
          base = %{
            "id" => target_id,
            "type" => to_string(source_trigger.type),
            "enabled" => source_trigger.enabled,
            "comment" => source_trigger.comment
          }

          # Add type-specific fields
          base
          |> maybe_add_webhook_fields(source_trigger)
          |> maybe_add_cron_fields(source_trigger)
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Mark unmatched target triggers for deletion
    deleted_targets =
      target_triggers
      |> Enum.filter(fn trigger ->
        not MapSet.member?(matched_target_ids, trigger.id)
      end)
      |> Enum.map(fn trigger ->
        %{
          "id" => trigger.id,
          "delete" => true
        }
      end)

    merged_from_source ++ deleted_targets
  end

  defp maybe_add_webhook_fields(base, trigger) do
    if trigger.type == :webhook do
      Map.put(base, "custom_path", trigger.custom_path)
    else
      base
    end
  end

  defp maybe_add_cron_fields(base, trigger) do
    if trigger.type == :cron do
      Map.put(base, "cron_expression", trigger.cron_expression)
    else
      base
    end
  end

  defp build_id_map(job_matches, trigger_matches) do
    Map.merge(job_matches, trigger_matches)
  end

  defp build_merged_edges(source_edges, id_map) do
    Enum.map(source_edges, fn edge ->
      %{
        "id" => edge.id,
        "source_trigger_id" =>
          if(edge.source_trigger_id,
            do: Map.get(id_map, edge.source_trigger_id),
            else: nil
          ),
        "source_job_id" =>
          if(edge.source_job_id,
            do: Map.get(id_map, edge.source_job_id),
            else: nil
          ),
        "target_job_id" =>
          if(edge.target_job_id,
            do: Map.get(id_map, edge.target_job_id),
            else: nil
          ),
        "condition_type" => to_string(edge.condition_type),
        "condition_expression" => edge.condition_expression,
        "condition_label" => edge.condition_label,
        "enabled" => edge.enabled
      }
    end)
  end
end
