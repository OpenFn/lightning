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
  Merges a sandbox workflow back onto its parent workflow using UUID mapping.

  Maps nodes and edges from source to target workflow, preserving UUIDs where
  possible when merging two workflows (likely one is a fork of the other).

  The algorithm follows these phases:
  1. Direct ID Matching - matches nodes with identical IDs
  2. Root Node Mapping - always maps root nodes
  3. Structural and Expression Matching - iterative matching using parents, children, and expression
  4. Edge Mapping - maps edges based on node mappings

  ## Parameters
    * `source_workflow` - The sandbox workflow with modifications
    * `target_workflow` - The parent workflow to merge changes onto

  ## Returns
    A map with the merged workflow structure ready for import, containing
    UUID mappings and workflow data.
  """
  @spec merge_workflow(Workflow.t(), Workflow.t()) :: map()
  def merge_workflow(
        %Workflow{} = source_workflow,
        %Workflow{} = target_workflow
      ) do
    source_workflow = Repo.preload(source_workflow, [:jobs, :triggers, :edges])
    target_workflow = Repo.preload(target_workflow, [:jobs, :triggers, :edges])

    node_mappings = map_workflow_node_ids(source_workflow, target_workflow)

    # Build the merged workflow structure using the mappings
    build_merged_workflow(
      source_workflow,
      target_workflow,
      node_mappings
    )
  end

  defp map_workflow_node_ids(source_workflow, target_workflow) do
    node_mappings = %{}

    # Phase 1: Direct ID Matching
    node_mappings =
      match_nodes_by_id(node_mappings, source_workflow, target_workflow)

    # Phase 2: Triggers Mapping
    node_mappings = map_triggers(node_mappings, source_workflow, target_workflow)

    # Phase 3: Structural and Expression Matching
    map_jobs(
      node_mappings,
      source_workflow,
      target_workflow
    )
  end

  # source -> target map
  defp match_nodes_by_id(node_mappings, source_workflow, target_workflow) do
    source_nodes = get_all_nodes(source_workflow)
    target_nodes = get_all_nodes(target_workflow)

    Enum.reduce(
      source_nodes,
      node_mappings,
      fn source_node, acc ->
        target_node = find_node_by_id(target_nodes, source_node.id)

        if target_node do
          Map.put(acc, source_node.id, target_node.id)
        else
          acc
        end
      end
    )
  end

  defp map_triggers(node_mappings, %{triggers: [source_trigger]}, %{
         triggers: [target_trigger]
       }) do
    Map.put(node_mappings, source_trigger.id, target_trigger.id)
  end

  defp map_triggers(node_mappings, source_workflow, target_workflow) do
    source_workflow.triggers
    |> Enum.reject(fn trigger -> trigger.id in Map.keys(node_mappings) end)
    |> Enum.reduce(node_mappings, fn source_trigger, acc ->
      matched_target =
        find_matching_trigger(source_trigger, target_workflow.triggers, acc)

      if matched_target do
        Map.put(acc, source_trigger.id, matched_target.id)
      else
        acc
      end
    end)
  end

  defp find_matching_trigger(source_trigger, target_triggers, node_mappings) do
    # Filter out already mapped triggers
    # Match trigger by type

    target_triggers
    |> Enum.reject(fn target ->
      target.id in Map.values(node_mappings)
    end)
    |> Enum.find(fn target ->
      target.type == source_trigger.type
    end)
  end

  defp map_jobs(
         node_mappings,
         source_workflow,
         target_workflow
       ) do
    source_adjacency_map = build_workflow_parent_children_map(source_workflow)
    target_adjacency_map = build_workflow_parent_children_map(target_workflow)

    all_matching_scores =
      Map.new(source_workflow.jobs, fn source_job ->
        scores =
          calculate_job_match_scores(
            source_job,
            source_workflow,
            source_adjacency_map,
            target_workflow,
            target_adjacency_map
          )

        {source_job.id, scores}
      end)

    # Transform scores to find best source matches for each target job
    # Result: %{target_job_id => [source_job1, source_job2, ...]} sorted by match score
    ranked_source_jobs_per_target =
      Map.new(target_workflow.jobs, fn target_job ->
        source_jobs = sort_matching_source_jobs(target_job, all_matching_scores)

        {target_job.id, source_jobs}
      end)

    # Create stable mappings using recursive matching
    # Each source job tries to match with its best target, but only succeeds if:
    # 1. The target's better choices (if any) can match elsewhere
    # 2. Or this source is the target's best available choice

    Enum.reduce(source_workflow.jobs, node_mappings, fn source_job, mappings ->
      try_match_source_job(
        source_job.id,
        all_matching_scores,
        ranked_source_jobs_per_target,
        mappings
      )
    end)
  end

  # Recursively try to match a source job with its best available target
  defp try_match_source_job(
         source_job_id,
         all_matching_scores,
         ranked_source_jobs_per_target,
         mappings
       ) do
    # Skip if already mapped
    if Map.has_key?(mappings, source_job_id) do
      mappings
    else
      # Get targets for this source and sort by total score
      sorted_targets =
        all_matching_scores
        |> Map.get(source_job_id, %{})
        |> Enum.sort_by(
          fn {_target_id, scores} ->
            scores |> Map.values() |> Enum.sum()
          end,
          :desc
        )
        |> Enum.map(fn {target_id, _} -> target_id end)

      # Try to match with each target in order of preference
      try_match_with_targets(
        source_job_id,
        sorted_targets,
        all_matching_scores,
        ranked_source_jobs_per_target,
        mappings
      )
    end
  end

  defp try_match_with_targets(
         _source_job_id,
         [],
         _all_matching_scores,
         _ranked_source_jobs_per_target,
         mappings
       ) do
    # No more targets to try
    mappings
  end

  defp try_match_with_targets(
         source_job_id,
         [target_id | rest_targets],
         all_matching_scores,
         ranked_source_jobs_per_target,
         mappings
       ) do
    # Skip if target is already mapped
    if target_id in Map.values(mappings) do
      try_match_with_targets(
        source_job_id,
        rest_targets,
        all_matching_scores,
        ranked_source_jobs_per_target,
        mappings
      )
    else
      # Check if we can claim this target
      if can_claim_target?(
           source_job_id,
           target_id,
           all_matching_scores,
           ranked_source_jobs_per_target,
           mappings
         ) do
        # We can claim it!
        Map.put(mappings, source_job_id, target_id)
      else
        # Can't claim this target, try next
        try_match_with_targets(
          source_job_id,
          rest_targets,
          all_matching_scores,
          ranked_source_jobs_per_target,
          mappings
        )
      end
    end
  end

  # Check if a source can claim a target
  # Returns true if either:
  # 1. This source is the target's best unmapped choice
  # 2. All better choices for the target can match elsewhere
  defp can_claim_target?(
         source_job_id,
         target_id,
         all_matching_scores,
         ranked_source_jobs_per_target,
         mappings
       ) do
    # Get all source jobs ranked for this target
    target_preferences = Map.get(ranked_source_jobs_per_target, target_id, [])

    # Find unmapped sources that this target prefers
    better_sources =
      target_preferences
      |> Enum.take_while(fn s -> s != source_job_id end)
      |> Enum.filter(fn s -> not Map.has_key?(mappings, s) end)

    # If no better unmapped sources, we can claim
    if Enum.empty?(better_sources) do
      true
    else
      # Check if all better sources can match with other targets they prefer more
      Enum.all?(better_sources, fn better_source_id ->
        can_match_elsewhere?(
          better_source_id,
          target_id,
          all_matching_scores,
          ranked_source_jobs_per_target,
          mappings
        )
      end)
    end
  end

  # Check if a source can match with a target other than the given excluded_target
  defp can_match_elsewhere?(
         source_job_id,
         excluded_target_id,
         all_matching_scores,
         ranked_source_jobs_per_target,
         mappings
       ) do
    # Get this source's preferences
    source_targets = Map.get(all_matching_scores, source_job_id, [])

    # Get targets this source prefers over or equal to the excluded target
    preferred_targets =
      source_targets
      |> Enum.take_while(fn {target_id, _} ->
        # Take targets until we reach the excluded one (not including it)
        target_id != excluded_target_id
      end)
      |> Enum.map(fn {target_id, _} -> target_id end)
      |> Enum.reject(fn target_id ->
        # Only consider unmapped targets
        target_id in Map.values(mappings)
      end)

    # Check if source can claim any of these preferred targets
    Enum.any?(preferred_targets, fn alt_target_id ->
      # Recursively check if source can claim this alternative target
      can_claim_target?(
        source_job_id,
        alt_target_id,
        all_matching_scores,
        ranked_source_jobs_per_target,
        mappings
      )
    end)
  end

  defp sort_matching_source_jobs(target_job, source_jobs_matching_scores) do
    source_jobs_matching_scores
    |> Enum.map(fn {source_job_id, target_scores} ->
      scores = Map.get(target_scores, target_job.id)

      # Calculate total score (sum of all individual scores)
      total_score =
        if scores do
          scores |> Map.values() |> Enum.sum()
        else
          0
        end

      {source_job_id, total_score}
    end)
    |> Enum.sort_by(fn {_source_job_id, score} -> score end, :desc)
    |> Enum.map(fn {source_job_id, _score} -> source_job_id end)
  end

  defp calculate_job_match_scores(
         source_job,
         _source_workflow,
         source_adjacency_map,
         target_workflow,
         target_adjacency_map
       ) do
    source_depths = calculate_node_depth(source_adjacency_map, source_job.id)

    {source_adaptor, _vsn} =
      Lightning.AdaptorRegistry.resolve_package_name(source_job.adaptor)

    # Calculate scores for each target job
    Enum.reduce(target_workflow.jobs, %{}, fn target_job, acc ->
      name_score =
        String.jaro_distance(source_job.name || "", target_job.name || "")

      {target_adaptor, _vsn} =
        Lightning.AdaptorRegistry.resolve_package_name(target_job.adaptor)

      adaptor_score = if target_adaptor == source_adaptor, do: 1, else: 0

      target_depths = calculate_node_depth(target_adjacency_map, target_job.id)

      depth_score =
        if Enum.any?(source_depths, &(&1 in target_depths)), do: 1, else: 0

      Map.put(acc, target_job.id, %{
        name: name_score,
        adaptor: adaptor_score,
        depth: depth_score
      })
    end)
  end

  # Get all nodes from a workflow (jobs + triggers)
  defp get_all_nodes(workflow) do
    workflow.jobs ++ workflow.triggers
  end

  defp find_node_by_id(nodes, id) do
    Enum.find(nodes, &(&1.id == id))
  end

  # Get all edges as parent -> [children] map
  defp build_workflow_parent_children_map(workflow) do
    Enum.reduce(workflow.edges, %{}, fn edge, acc ->
      parent_id = edge.source_trigger_id || edge.source_job_id
      child_id = edge.target_job_id

      if parent_id && child_id do
        Map.update(acc, parent_id, [child_id], fn children ->
          [child_id | children]
        end)
      else
        acc
      end
    end)
  end

  # Calculate all possible depths of a node in the workflow DAG
  # Returns a list of depths from all possible paths
  # Depth starts at 1 for root nodes
  defp calculate_node_depth(parent_children_map, node_id) do
    parents =
      parent_children_map
      |> Enum.filter(fn {_parent_id, children} ->
        node_id in children
      end)
      |> Enum.map(fn {parent_id, _children} -> parent_id end)

    if Enum.empty?(parents) do
      # This is a root node
      [1]
    else
      # The + 1 represents moving one level deeper in the DAG.
      # Each child is one step further from the root than its parent.
      parents
      |> Enum.flat_map(fn parent_id ->
        calculate_node_depth(parent_children_map, parent_id)
      end)
      |> Enum.map(&(&1 + 1))
      |> Enum.uniq()
      |> Enum.sort()
    end
  end

  defp find_edge(edges, source_node_id, target_node_id) do
    Enum.find(edges, fn edge ->
      from_id =
        Map.get(edge, :source_job_id) || Map.fetch(edge, :source_trigger_id)

      to_id = Map.get(edge, :target_job_id)

      from_id == source_node_id and to_id == target_node_id
    end)
  end

  # Build the final merged workflow structure
  defp build_merged_workflow(source_workflow, target_workflow, node_mappings) do
    # Separate job and trigger mappings
    source_trigger_ids = Enum.map(source_workflow.triggers, & &1.id)

    {trigger_mappings, job_mappings} =
      Map.split(node_mappings, source_trigger_ids)

    # Build merged components
    {job_mappings, merged_jobs} =
      build_merged_jobs(
        source_workflow.jobs,
        target_workflow.jobs,
        job_mappings
      )

    {trigger_mappings, merged_triggers} =
      build_merged_triggers(
        source_workflow.triggers,
        target_workflow.triggers,
        trigger_mappings
      )

    # Build complete ID map for edge remapping
    node_mappings = Map.merge(job_mappings, trigger_mappings)

    merged_edges =
      build_merged_edges(
        source_workflow.edges,
        target_workflow.edges,
        node_mappings
      )

    initial_positions = Map.get(source_workflow, :positions) || %{}

    merged_positions =
      Map.new(initial_positions, fn {job_id, position} ->
        {Map.fetch(node_mappings, job_id), position}
      end)

    source_workflow
    |> Map.take([:name, :concurrency, :enable_job_logs])
    |> Lightning.Utils.Maps.stringify_keys()
    |> Map.merge(%{
      "id" => target_workflow.id,
      "positions" => merged_positions,
      "jobs" => merged_jobs,
      "triggers" => merged_triggers,
      "edges" => merged_edges
    })
  end

  defp build_merged_jobs(source_jobs, target_jobs, job_mappings) do
    # Process source jobs (matched and new)
    {new_mapping, merged_from_source} =
      Enum.reduce(
        source_jobs,
        {%{}, []},
        fn source_job, {new_mapping, merged_jobs} ->
          mapped_id =
            Map.get(job_mappings, source_job.id) || Ecto.UUID.generate()

          merged_job =
            source_job
            |> Map.take([
              :name,
              :body,
              :adaptor,
              :project_credential_id,
              :keychain_credential_id
            ])
            |> Map.put(:id, mapped_id)
            |> Lightning.Utils.Maps.stringify_keys()

          {Map.put(new_mapping, source_job.id, mapped_id),
           [merged_job | merged_jobs]}
        end
      )

    # Mark unmatched target jobs for deletion
    deleted_targets =
      target_jobs
      |> Enum.reject(fn job ->
        job.id in Map.values(job_mappings)
      end)
      |> Enum.map(fn job ->
        %{"id" => job.id, "delete" => true}
      end)

    {new_mapping, merged_from_source ++ deleted_targets}
  end

  defp build_merged_triggers(source_triggers, target_triggers, trigger_mappings) do
    # Process source triggers (matched and new)
    {new_mapping, merged_from_source} =
      Enum.reduce(
        source_triggers,
        {%{}, []},
        fn source_trigger, {new_mapping, merged_triggers} ->
          mapped_id =
            Map.get(trigger_mappings, source_trigger.id) || Ecto.UUID.generate()

          merged_trigger =
            source_trigger
            |> Map.take([
              :comment,
              :custom_path,
              :cron_expression,
              :type,
              :kafka_configuration
            ])
            |> Map.put(:id, mapped_id)
            |> Lightning.Utils.Maps.stringify_keys()

          {Map.put(new_mapping, source_trigger.id, mapped_id),
           [merged_trigger | merged_triggers]}
        end
      )

    # Mark unmatched target triggers for deletion
    deleted_targets =
      target_triggers
      |> Enum.reject(fn trigger ->
        trigger.id in Map.values(trigger_mappings)
      end)
      |> Enum.map(fn trigger ->
        %{"id" => trigger.id, "delete" => true}
      end)

    {new_mapping, merged_from_source ++ deleted_targets}
  end

  defp build_merged_edges(source_edges, target_edges, node_mappings) do
    merged_from_source =
      Enum.map(source_edges, fn source_edge ->
        from_id =
          Map.get(source_edge, :source_trigger_id) ||
            Map.get(source_edge, :source_job_id)

        mapped_from_id = Map.fetch!(node_mappings, from_id)
        to_id = Map.get(source_edge, :target_job_id)
        mapped_to_id = Map.fetch!(node_mappings, to_id)

        target_edge = find_edge(target_edges, mapped_from_id, mapped_to_id)

        mapped_id =
          if target_edge, do: target_edge.id, else: Ecto.UUID.generate()

        source_edge
        |> Map.take([
          :condition_type,
          :condition_expression,
          :condition_label,
          :enabled
        ])
        |> Map.merge(%{
          id: mapped_id,
          source_job_id: Map.get(source_edge, :source_job_id) && mapped_from_id,
          source_trigger_id:
            Map.get(source_edge, :source_trigger_id) && mapped_from_id,
          target_job_id: mapped_to_id
        })
        |> Lightning.Utils.Maps.stringify_keys()
      end)

    merged_trigger_ids = Enum.map(merged_from_source, fn edge -> edge["id"] end)

    # Mark unmatched target edges for deletion
    deleted_targets =
      target_edges
      |> Enum.reject(fn trigger ->
        trigger.id in merged_trigger_ids
      end)
      |> Enum.map(fn trigger ->
        %{"id" => trigger.id, "delete" => true}
      end)

    merged_from_source ++ deleted_targets
  end
end
