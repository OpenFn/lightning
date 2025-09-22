defmodule Lightning.Projects.MergeProjects do
  @moduledoc """
  Responsible for merging 2 different projects. Used by sandboxes to merge
  sandbox workflows back onto their parent workflows.
  """
  import Lightning.Utils.Maps, only: [stringify_keys: 1]

  alias Lightning.AdaptorRegistry
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow

  @doc """
  Merges a source project onto a target project using workflow name matching.

  Maps workflows from source to target project based on exact name matching.
  Uses the existing merge_workflow/2 logic for individual workflow merging.
  Workflows that don't match are marked for deletion (target) or creation (source).

  ## Parameters
    * `source_project` - The project with modifications to merge
    * `target_project` - The target project to merge changes onto

  ## Returns
    A map with the merged project structure ready for import, containing
    workflow mappings and project data.
  """
  @spec merge_project(Project.t(), Project.t()) :: map()
  def merge_project(
        %Project{} = source_project,
        %Project{} = target_project
      ) do
    source_project =
      Repo.preload(source_project, workflows: [:jobs, :triggers, :edges])

    target_project =
      Repo.preload(target_project, workflows: [:jobs, :triggers, :edges])

    merge_project(
      Map.from_struct(source_project),
      Map.from_struct(target_project)
    )
  end

  def merge_project(source_project, target_project) do
    workflow_mappings =
      map_project_workflow_names(source_project, target_project)

    # Build the merged project structure using the mappings
    build_merged_project(
      source_project,
      target_project,
      workflow_mappings
    )
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

    merge_workflow(
      Map.from_struct(source_workflow),
      Map.from_struct(target_workflow)
    )
  end

  def merge_workflow(source_workflow, target_workflow) do
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
      AdaptorRegistry.resolve_package_name(source_job.adaptor)

    # Calculate scores for each target job
    Enum.reduce(target_workflow.jobs, %{}, fn target_job, acc ->
      name_score =
        String.jaro_distance(source_job.name || "", target_job.name || "")

      {target_adaptor, _vsn} =
        AdaptorRegistry.resolve_package_name(target_job.adaptor)

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
        Map.get(edge, :source_job_id) || Map.get(edge, :source_trigger_id)

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
        {Map.get(node_mappings, job_id), position}
      end)
      |> Map.new()

    source_workflow
    |> Map.take([:name, :concurrency, :enable_job_logs])
    |> stringify_keys()
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
            |> stringify_keys()

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
            |> stringify_keys()

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
        |> stringify_keys()
      end)

    merged_edge_ids = Enum.map(merged_from_source, fn edge -> edge["id"] end)

    # Mark unmatched target edges for deletion
    deleted_targets =
      target_edges
      |> Enum.reject(fn edge ->
        edge.id in merged_edge_ids
      end)
      |> Enum.map(fn edge ->
        %{"id" => edge.id, "delete" => true}
      end)

    merged_from_source ++ deleted_targets
  end

  # Project merging helper functions

  defp map_project_workflow_names(source_project, target_project) do
    # Map source workflow names to target workflow IDs using exact name matching
    source_project.workflows
    |> Enum.reduce(%{}, fn source_workflow, acc ->
      target_workflow =
        find_workflow_by_name(target_project.workflows, source_workflow.name)

      if target_workflow do
        Map.put(acc, source_workflow.id, target_workflow.id)
      else
        acc
      end
    end)
  end

  defp find_workflow_by_name(workflows, name) do
    Enum.find(workflows, &(&1.name == name))
  end

  defp build_merged_project(source_project, target_project, workflow_mappings) do
    merged_workflows =
      build_merged_workflows(
        source_project.workflows,
        target_project.workflows,
        workflow_mappings
      )

    source_project
    |> Map.take([:name, :description])
    |> stringify_keys()
    |> Map.merge(%{
      "id" => target_project.id,
      "workflows" => merged_workflows
    })
  end

  defp build_merged_workflows(
         source_workflows,
         target_workflows,
         workflow_mappings
       ) do
    # Process source workflows (matched and new)
    merged_from_source =
      Enum.map(source_workflows, fn source_workflow ->
        case Map.get(workflow_mappings, source_workflow.id) do
          nil ->
            # New workflow - generate new UUID
            source_workflow
            |> Map.take([:name, :concurrency, :enable_job_logs])
            |> Map.put(:id, Ecto.UUID.generate())
            |> stringify_keys()

          target_id ->
            # Matched workflow - merge using existing merge_workflow logic
            target_workflow = Enum.find(target_workflows, &(&1.id == target_id))
            merge_workflow(source_workflow, target_workflow)
        end
      end)

    # Mark unmatched target workflows for deletion
    deleted_targets =
      target_workflows
      |> Enum.reject(fn workflow ->
        workflow.id in Map.values(workflow_mappings)
      end)
      |> Enum.map(fn workflow ->
        %{"id" => workflow.id, "delete" => true}
      end)

    merged_from_source ++ deleted_targets
  end
end
