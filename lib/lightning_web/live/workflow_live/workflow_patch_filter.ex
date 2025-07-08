defmodule LightningWeb.WorkflowLive.WorkflowPatchFilter do
  @doc """
  Filters JSON patch operations to remove ID regeneration noise while preserving
  all meaningful changes. Adjusts reference IDs to use original IDs where applicable.
  """
  # In your filter_meaningful_patches function, add some logging:
  def filter_meaningful_patches(patches, ai_params, original_params) do
    id_mapping = build_id_mapping_from_params(ai_params, original_params)

    filtered =
      patches
      |> Enum.map(&process_patch(&1, id_mapping))
      |> Enum.filter(&(&1 != :drop))

    # Debug: What patches are we dropping?
    dropped = patches -- filtered
    IO.inspect(dropped, label: "DROPPED PATCHES")
    IO.inspect(filtered, label: "KEPT PATCHES")

    filtered
  end

  # Build mapping by comparing structures with hybrid approach
  def build_id_mapping_from_params(ai_params, original_params) do
    %{}
    |> map_triggers(ai_params, original_params)
    |> map_jobs_hybrid(ai_params, original_params)
    |> map_edges_by_pattern(ai_params, original_params)
  end

  # Triggers: Match by type (only one webhook allowed)
  defp map_triggers(mapping, ai_params, original_params) do
    ai_triggers = Map.get(ai_params, "triggers", [])
    orig_triggers = Map.get(original_params, "triggers", [])

    case {ai_triggers, orig_triggers} do
      {[ai_trigger], [orig_trigger]} ->
        # Single trigger each - safe to map
        if ai_trigger["id"] != orig_trigger["id"] do
          Map.put(mapping, ai_trigger["id"], orig_trigger["id"])
        else
          mapping
        end

      _ ->
        # Multiple triggers or mismatch - don't map
        mapping
    end
  end

  # Jobs: Hybrid approach - name first, then position for unmatched
  defp map_jobs_hybrid(mapping, ai_params, original_params) do
    ai_jobs = Map.get(ai_params, "jobs", [])
    orig_jobs = Map.get(original_params, "jobs", [])

    # Phase 1: Exact name matching
    {mapping_after_names, matched_ai_indices, matched_orig_indices} =
      map_jobs_by_name(mapping, ai_jobs, orig_jobs)

    # Phase 2: Position matching for unmatched (likely renames)
    unmatched_ai = get_unmatched_with_indices(ai_jobs, matched_ai_indices)
    unmatched_orig = get_unmatched_with_indices(orig_jobs, matched_orig_indices)

    if length(unmatched_ai) == length(unmatched_orig) and
         length(unmatched_ai) > 0 do
      # Same number of unmatched - likely renames, use position
      map_remaining_by_position(
        mapping_after_names,
        unmatched_ai,
        unmatched_orig
      )
    else
      mapping_after_names
    end
  end

  defp map_jobs_by_name(mapping, ai_jobs, orig_jobs) do
    # Build name lookup
    orig_by_name =
      orig_jobs
      |> Enum.with_index()
      |> Map.new(fn {job, idx} -> {job["name"], {job, idx}} end)

    {updated_mapping, matched_ai_indices, matched_orig_indices} =
      ai_jobs
      |> Enum.with_index()
      |> Enum.reduce({mapping, MapSet.new(), MapSet.new()}, fn {ai_job, ai_idx},
                                                               {acc, ai_indices,
                                                                orig_indices} ->
        case Map.get(orig_by_name, ai_job["name"]) do
          nil ->
            {acc, ai_indices, orig_indices}

          {orig_job, orig_idx} ->
            if orig_idx not in orig_indices do
              new_ai_indices = MapSet.put(ai_indices, ai_idx)
              new_orig_indices = MapSet.put(orig_indices, orig_idx)

              new_mapping =
                if ai_job["id"] != orig_job["id"] do
                  Map.put(acc, ai_job["id"], orig_job["id"])
                else
                  acc
                end

              {new_mapping, new_ai_indices, new_orig_indices}
            else
              {acc, ai_indices, orig_indices}
            end
        end
      end)

    {updated_mapping, matched_ai_indices, matched_orig_indices}
  end

  defp get_unmatched_with_indices(jobs, matched_indices) do
    jobs
    |> Enum.with_index()
    |> Enum.reject(fn {_, idx} -> idx in matched_indices end)
  end

  defp map_remaining_by_position(mapping, unmatched_ai, unmatched_orig) do
    # Sort by original index to maintain relative order
    sorted_ai = Enum.sort_by(unmatched_ai, fn {_, idx} -> idx end)
    sorted_orig = Enum.sort_by(unmatched_orig, fn {_, idx} -> idx end)

    Enum.zip(sorted_ai, sorted_orig)
    |> Enum.reduce(mapping, fn {{ai_job, _}, {orig_job, _}}, acc ->
      if ai_job["id"] != orig_job["id"] do
        Map.put(acc, ai_job["id"], orig_job["id"])
      else
        acc
      end
    end)
  end

  # Edges: Match by connection pattern
  defp map_edges_by_pattern(mapping, ai_params, original_params) do
    ai_edges = Map.get(ai_params, "edges", [])
    orig_edges = Map.get(original_params, "edges", [])

    # Build pattern lookup for original edges
    orig_patterns =
      orig_edges
      |> Map.new(fn edge ->
        pattern = edge_pattern(edge)
        {pattern, edge}
      end)

    # Map edges that have the same pattern
    ai_edges
    |> Enum.reduce(mapping, fn ai_edge, acc ->
      # Adjust pattern to use original IDs
      adjusted_pattern = adjust_edge_pattern(ai_edge, mapping)

      case Map.get(orig_patterns, adjusted_pattern) do
        nil ->
          acc

        orig_edge ->
          if ai_edge["id"] != orig_edge["id"] do
            Map.put(acc, ai_edge["id"], orig_edge["id"])
          else
            acc
          end
      end
    end)
  end

  defp edge_pattern(edge) do
    {
      edge["source_trigger_id"] || edge["source_job_id"],
      edge["target_job_id"],
      edge["condition_type"]
    }
  end

  defp adjust_edge_pattern(edge, mapping) do
    source_id = edge["source_trigger_id"] || edge["source_job_id"]
    target_id = edge["target_job_id"]

    {
      Map.get(mapping, source_id, source_id),
      Map.get(mapping, target_id, target_id),
      edge["condition_type"]
    }
  end

  # Process each patch according to our rules
  def process_patch(patch, id_mapping) do
    case patch do
      # Rule 1: DROP ID replacements
      %Jsonpatch.Operation.Replace{path: path} ->
        if is_id_path?(path) do
          :drop
        else
          # Check if it's a reference path
          if is_reference_path?(path) do
            adjust_reference_id(patch, patch.value, id_mapping)
          else
            patch
          end
        end

      # Rule 1: DROP ID removals
      %Jsonpatch.Operation.Remove{path: "/id"} ->
        :drop

      # Rule 2: ADJUST reference IDs for Add operations
      %Jsonpatch.Operation.Add{path: path, value: value} = op ->
        if is_reference_path?(path) do
          adjust_reference_id(op, value, id_mapping)
        else
          op
        end

      # Rules 3, 4, 5: KEEP everything else
      other ->
        other
    end
  end

  # Check if path is an ID field
  defp is_id_path?(path) do
    String.ends_with?(path, "/id")
  end

  # Check if path is a reference field
  defp is_reference_path?(path) do
    String.ends_with?(path, "_id") and not String.ends_with?(path, "/id")
  end

  # Adjust reference IDs using our mapping
  defp adjust_reference_id(patch, value, id_mapping) when is_binary(value) do
    case Map.get(id_mapping, value) do
      nil ->
        # Not in mapping - it's a new entity or unchanged, keep as-is
        patch

      original_id ->
        # Found in mapping - adjust to use original ID
        %{patch | value: original_id}
    end
  end

  defp adjust_reference_id(patch, _value, _id_mapping) do
    # Non-string value (maybe nil), keep as-is
    patch
  end
end
