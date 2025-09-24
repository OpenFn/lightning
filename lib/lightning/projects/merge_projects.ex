defmodule Lightning.Projects.MergeProjects do
  @moduledoc """
  Responsible for merging 2 different projects. Used by sandboxes to merge
  sandbox workflows back onto their parent workflows.
  """
  import Lightning.Utils.Maps, only: [stringify_keys: 1]

  # alias Lightning.AdaptorRegistry
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

    # Phase 1: Triggers Mapping
    node_mappings = map_triggers(node_mappings, source_workflow, target_workflow)

    # Phase 2: Jobs Mapping
    map_jobs(
      node_mappings,
      source_workflow,
      target_workflow
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

    # Step 1: Direct name matching
    node_mappings =
      match_jobs_by_name(node_mappings, source_workflow, target_workflow)

    # Step 2: Parent/children signature matching for remaining unmapped jobs
    node_mappings =
      match_jobs_by_signatures(
        node_mappings,
        source_workflow,
        target_workflow,
        source_adjacency_map,
        target_adjacency_map
      )

    # Step 3: Map any remaining unmapped source jobs to available target jobs
    map_remaining_jobs(
      node_mappings,
      source_workflow,
      target_workflow,
      source_adjacency_map,
      target_adjacency_map
    )
  end

  # Step 1: Match jobs by exact name
  defp match_jobs_by_name(node_mappings, source_workflow, target_workflow) do
    Enum.reduce(source_workflow.jobs, node_mappings, fn source_job, acc ->
      # Skip if already mapped
      if Map.has_key?(acc, source_job.id) do
        acc
      else
        # Find target job with exact name match
        target_job =
          Enum.find(target_workflow.jobs, fn target_job ->
            target_job.name == source_job.name and
              target_job.id not in Map.values(acc)
          end)

        if target_job do
          Map.put(acc, source_job.id, target_job.id)
        else
          acc
        end
      end
    end)
  end

  # Step 2: Match jobs by parent/children signatures (iterative)
  defp match_jobs_by_signatures(
         node_mappings,
         source_workflow,
         target_workflow,
         source_adjacency_map,
         target_adjacency_map
       ) do
    # Iterate until no more mappings are found
    iterate_signature_matching(
      node_mappings,
      source_workflow,
      target_workflow,
      source_adjacency_map,
      target_adjacency_map,
      _max_iterations = length(source_workflow.jobs)
    )
  end

  # Iteratively match jobs until no more progress is made
  defp iterate_signature_matching(
         node_mappings,
         source_workflow,
         target_workflow,
         source_adjacency_map,
         target_adjacency_map,
         max_iterations
       ) do
    if max_iterations <= 0 do
      node_mappings
    else
      new_mappings =
        attempt_signature_matching(
          node_mappings,
          source_workflow,
          target_workflow,
          source_adjacency_map,
          target_adjacency_map
        )

      # If no new mappings were found, we're done
      if map_size(new_mappings) == map_size(node_mappings) do
        new_mappings
      else
        # Continue iterating with new mappings
        iterate_signature_matching(
          new_mappings,
          source_workflow,
          target_workflow,
          source_adjacency_map,
          target_adjacency_map,
          max_iterations - 1
        )
      end
    end
  end

  # Single iteration of signature matching
  defp attempt_signature_matching(
         node_mappings,
         source_workflow,
         target_workflow,
         source_adjacency_map,
         target_adjacency_map,
         last_iteration? \\ false
       ) do
    # Get unmapped source jobs
    unmapped_source_jobs =
      Enum.reject(source_workflow.jobs, fn job ->
        Map.has_key?(node_mappings, job.id)
      end)
      |> Enum.sort_by(
        fn job ->
          parents = get_parents(job, source_adjacency_map)

          children =
            get_children(job, source_adjacency_map)

          Enum.count(parents) + Enum.count(children)
        end,
        :desc
      )

    # Process each unmapped source job
    Enum.reduce(unmapped_source_jobs, node_mappings, fn source_job, acc ->
      candidates =
        find_signature_candidates(
          source_job,
          target_workflow.jobs,
          acc,
          source_adjacency_map,
          target_adjacency_map
        )

      case candidates do
        [single_candidate] ->
          # Exactly one candidate - accept immediately
          Map.put(acc, source_job.id, single_candidate.id)

        multiple_candidates when length(multiple_candidates) > 1 ->
          # Multiple candidates - use job body matching
          body_matches = filter_matching_by_body(source_job, multiple_candidates)

          case body_matches do
            [single_match] ->
              Map.put(acc, source_job.id, single_match.id)

            [position_match | _rest] when last_iteration? ->
              Map.put(acc, source_job.id, position_match.id)

            _other ->
              acc
          end

        [] ->
          # No candidates - leave unmapped for this iteration
          acc
      end
    end)
  end

  # Find target job candidates based on parent/children signatures
  defp find_signature_candidates(
         source_job,
         target_jobs,
         node_mappings,
         source_adjacency_map,
         target_adjacency_map
       ) do
    # Get already mapped targets to exclude
    mapped_target_ids = Map.values(node_mappings)

    # Filter to unmapped target jobs
    available_targets =
      Enum.reject(target_jobs, fn job -> job.id in mapped_target_ids end)

    # Get parent and children signatures for source job
    mapped_source_parents =
      get_mapped_parents(source_job.id, source_adjacency_map, node_mappings)

    mapped_source_children =
      get_mapped_children(source_job.id, source_adjacency_map, node_mappings)

    target_candidates_from_parents =
      Enum.flat_map(mapped_source_parents, fn parent_id ->
        get_children(parent_id, target_adjacency_map)
      end)

    target_candidates_from_children =
      Enum.flat_map(mapped_source_children, fn child_id ->
        get_parents(child_id, target_adjacency_map)
      end)

    # Prioritize candidates that match both parent and children constraints
    candidates_from_both =
      MapSet.intersection(
        MapSet.new(target_candidates_from_parents),
        MapSet.new(target_candidates_from_children)
      )
      |> MapSet.to_list()

    candidate_ids =
      cond do
        # If we have candidates that satisfy both constraints, use only those
        length(candidates_from_both) > 0 ->
          candidates_from_both

        # If we have a single parent candidate, prefer it
        length(target_candidates_from_parents) == 1 ->
          target_candidates_from_parents

        # Otherwise, union parent and children candidates
        true ->
          MapSet.union(
            MapSet.new(target_candidates_from_parents),
            MapSet.new(target_candidates_from_children)
          )
          |> MapSet.to_list()
      end

    available_targets
    |> Enum.filter(fn target -> target.id in candidate_ids end)
    |> Enum.sort_by(
      fn target ->
        # Sort by number of children (desc), then by number of parents (desc) for tie-breaking
        children_count = target.id |> get_children(target_adjacency_map) |> Enum.count()
        parents_count = target.id |> get_parents(target_adjacency_map) |> Enum.count()
        {children_count, parents_count}
      end,
      :desc
    )
  end

  # Get mapped parent IDs for a source job
  defp get_mapped_parents(job_id, adjacency_map, node_mappings) do
    get_parents(job_id, adjacency_map)
    |> Enum.map(fn parent_id -> Map.get(node_mappings, parent_id) end)
    |> Enum.reject(&is_nil/1)
  end

  # Get mapped children IDs for a source job
  defp get_mapped_children(job_id, adjacency_map, node_mappings) do
    get_children(job_id, adjacency_map)
    |> Enum.map(fn child_id -> Map.get(node_mappings, child_id) end)
    |> Enum.reject(&is_nil/1)
  end

  # Get parent IDs for a job
  defp get_parents(job_id, adjacency_map) do
    adjacency_map
    |> Enum.filter(fn {_parent_id, children} -> job_id in children end)
    |> Enum.map(fn {parent_id, _children} -> parent_id end)
  end

  # Get children IDs for a job
  defp get_children(job_id, adjacency_map) do
    Map.get(adjacency_map, job_id, [])
  end

  # Find match among candidates using job body comparison
  defp filter_matching_by_body(source_job, candidates) do
    source_body = source_job.body || ""

    candidates
    |> Enum.filter(fn candidate ->
      candidate_body = candidate.body || ""
      String.trim(source_body) == String.trim(candidate_body)
    end)
  end

  # Step 3: Handle remaining unmapped jobs:
  # - if exactly 1 unmapped source and 1 unmapped target, map them together
  # - otherwise, attempt the signature mapping one last time.
  defp map_remaining_jobs(
         node_mappings,
         source_workflow,
         target_workflow,
         source_adjacency_map,
         target_adjacency_map
       ) do
    # Get unmapped source jobs
    unmapped_source_jobs =
      Enum.reject(source_workflow.jobs, fn job ->
        Map.has_key?(node_mappings, job.id)
      end)

    # Get unmapped target jobs
    mapped_target_ids = Map.values(node_mappings)

    unmapped_target_jobs =
      Enum.reject(target_workflow.jobs, fn job ->
        job.id in mapped_target_ids
      end)

    # Special case: exactly 1 unmapped source and 1 unmapped target
    case {unmapped_source_jobs, unmapped_target_jobs} do
      {[single_source], [single_target]} ->
        # Map the single remaining source to single remaining target
        Map.put(node_mappings, single_source.id, single_target.id)

      _ ->
        # attempt last signature mapping
        attempt_signature_matching(
          node_mappings,
          source_workflow,
          target_workflow,
          source_adjacency_map,
          target_adjacency_map,
          true
        )
    end
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
