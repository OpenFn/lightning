defmodule Lightning.Workflows.ParamsComparator do
  @moduledoc """
  Functions for comparing workflow structures and detecting changes.
  This module provides functionality to compare workflows semantically (ignoring IDs and
  metadata by default) or exactly (comparing all fields). It's useful for detecting
  structural changes, generating checksums for caching, and workflow versioning.
  """

  @doc """
  Compares two workflow structures to determine if they are semantically equivalent.
  ## Options
    * `:mode` - Either `:semantic` (default) or `:exact`
      - `:semantic` - Ignores IDs, timestamps, and other metadata
      - `:exact` - Compares all fields
    * `:ignore` - Nested keyword list of fields to ignore
      Format:
      ```elixir
      ignore: [
        workflow: [:name, :project_id],
        jobs: [:body, :adaptor],
        triggers: [:cron_expression, :custom_path],
        edges: [:enabled]
      ]
      ```
      Special values:
      - `jobs: :all` - Ignore all job fields
      - `triggers: :all` - Ignore all trigger fields
      - `edges: :all` - Ignore all edge fields
  """
  def equivalent?(workflow1, workflow2, opts \\ [])

  def equivalent?(nil, nil, _opts), do: true
  def equivalent?(nil, _workflow2, _opts), do: false
  def equivalent?(_workflow1, nil, _opts), do: false

  def equivalent?(workflow1, workflow2, opts) do
    checksum(workflow1, opts) == checksum(workflow2, opts)
  end

  defp checksum(workflow, opts) do
    ignore_list = build_ignore_list(opts)

    workflow
    |> normalize_workflow(ignore_list)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Default fields to ignore for semantic comparison
  @semantic_defaults [
    workflow: [
      :id,
      :project_id,
      :lock_version,
      :deleted_at,
      :delete,
      :inserted_at,
      :updated_at,
      :concurrency,
      :enable_job_logs,
      :errors,
      :positions
    ],
    jobs: [
      :id,
      :inserted_at,
      :updated_at,
      :delete,
      :project_credential_id,
      :workflow_id
    ],
    triggers: [
      :id,
      :inserted_at,
      :updated_at,
      :delete,
      :has_auth_method,
      :workflow_id,
      :comment,
      :custom_path
    ],
    edges: [:id, :inserted_at, :updated_at, :delete, :workflow_id]
  ]

  # Define all fields for each entity type (for :all option)
  @workflow_fields [
    :id,
    :name,
    :project_id,
    :lock_version,
    :deleted_at,
    :delete,
    :inserted_at,
    :updated_at,
    :concurrency,
    :enable_job_logs,
    :positions,
    :errors
  ]

  @job_fields [
    :id,
    :name,
    :body,
    :adaptor,
    :project_credential_id,
    :workflow_id,
    :inserted_at,
    :updated_at,
    :delete,
    :errors
  ]

  @trigger_fields [
    :id,
    :type,
    :enabled,
    :cron_expression,
    :kafka_configuration,
    :has_auth_method,
    :comment,
    :custom_path,
    :workflow_id,
    :inserted_at,
    :updated_at,
    :delete,
    :errors
  ]

  @edge_fields [
    :id,
    :source_job_id,
    :source_trigger_id,
    :target_job_id,
    :enabled,
    :condition_type,
    :condition_expression,
    :condition_label,
    :workflow_id,
    :inserted_at,
    :updated_at,
    :delete,
    :errors
  ]

  defp build_ignore_list(opts) do
    mode = Keyword.get(opts, :mode, :semantic)
    custom_ignore = Keyword.get(opts, :ignore, [])

    base_ignore =
      case mode do
        :exact -> []
        :semantic -> flatten_ignore_list(@semantic_defaults)
        _ -> flatten_ignore_list(@semantic_defaults)
      end

    flat_custom_ignore = flatten_ignore_list(custom_ignore)

    Enum.uniq(base_ignore ++ flat_custom_ignore)
  end

  defp flatten_ignore_list(ignore_list) when is_list(ignore_list) do
    Enum.flat_map(ignore_list, fn
      {:workflow, fields} ->
        flatten_workflow_fields(fields)

      {:jobs, fields} ->
        flatten_with_prefix(fields, "job_", @job_fields)

      {:triggers, fields} ->
        flatten_with_prefix(fields, "trigger_", @trigger_fields)

      {:edges, fields} ->
        flatten_with_prefix(fields, "edge_", @edge_fields)
    end)
  end

  defp flatten_workflow_fields(:all), do: @workflow_fields
  defp flatten_workflow_fields(fields) when is_list(fields), do: fields

  defp flatten_with_prefix(:all, prefix, all_fields) do
    Enum.map(all_fields, fn
      :id -> :"#{prefix}ids"
      field -> :"#{prefix}#{field}"
    end)
  end

  defp flatten_with_prefix(fields, prefix, _all_fields) when is_list(fields) do
    Enum.map(fields, fn
      :id -> :"#{prefix}ids"
      field -> :"#{prefix}#{field}"
    end)
  end

  defp normalize_workflow(workflow, ignore_list) do
    normalized = %{}

    normalized =
      add_unless_ignored(normalized, :id, get_field(workflow, "id"), ignore_list)

    normalized =
      add_unless_ignored(
        normalized,
        :name,
        get_field(workflow, "name"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :project_id,
        get_field(workflow, "project_id"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :lock_version,
        get_field(workflow, "lock_version"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :deleted_at,
        get_field(workflow, "deleted_at"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :inserted_at,
        get_field(workflow, "inserted_at"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :updated_at,
        get_field(workflow, "updated_at"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :concurrency,
        get_field(workflow, "concurrency"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :enable_job_logs,
        get_field(workflow, "enable_job_logs"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :positions,
        get_field(workflow, "positions"),
        ignore_list
      )

    normalized =
      add_unless_ignored(
        normalized,
        :errors,
        get_field(workflow, "errors"),
        ignore_list
      )

    normalized
    |> Map.put(
      :jobs,
      normalize_jobs(get_field(workflow, "jobs") || [], ignore_list)
    )
    |> Map.put(
      :triggers,
      normalize_triggers(get_field(workflow, "triggers") || [], ignore_list)
    )
    |> Map.put(
      :edges,
      normalize_edges(get_field(workflow, "edges") || [], workflow, ignore_list)
    )
  end

  defp normalize_jobs(jobs, ignore_list) do
    ignoring_ids = :job_ids in ignore_list

    jobs
    |> Enum.map(fn job ->
      normalized = %{}

      normalized =
        add_unless_ignored(
          normalized,
          :name,
          get_field(job, "name"),
          ignore_list,
          :job_name
        )

      normalized =
        add_unless_ignored(
          normalized,
          :id,
          get_field(job, "id"),
          ignore_list,
          :job_ids
        )

      normalized =
        add_unless_ignored(
          normalized,
          :body,
          get_field(job, "body"),
          ignore_list,
          :job_body
        )

      normalized =
        add_unless_ignored(
          normalized,
          :adaptor,
          get_field(job, "adaptor"),
          ignore_list,
          :job_adaptor
        )

      normalized =
        add_unless_ignored(
          normalized,
          :project_credential_id,
          get_field(job, "project_credential_id"),
          ignore_list,
          :job_project_credential_id
        )

      normalized =
        add_unless_ignored(
          normalized,
          :workflow_id,
          get_field(job, "workflow_id"),
          ignore_list,
          :job_workflow_id
        )

      normalized =
        add_unless_ignored(
          normalized,
          :inserted_at,
          get_field(job, "inserted_at"),
          ignore_list,
          :job_inserted_at
        )

      normalized =
        add_unless_ignored(
          normalized,
          :updated_at,
          get_field(job, "updated_at"),
          ignore_list,
          :job_updated_at
        )

      normalized =
        add_unless_ignored(
          normalized,
          :delete,
          get_field(job, "delete"),
          ignore_list,
          :job_delete
        )

      normalized =
        add_unless_ignored(
          normalized,
          :errors,
          get_field(job, "errors"),
          ignore_list,
          :job_errors
        )

      normalized
    end)
    |> Enum.sort_by(fn job ->
      if ignoring_ids, do: job[:name], else: job[:id]
    end)
  end

  defp normalize_triggers(triggers, ignore_list) do
    ignoring_ids = :trigger_ids in ignore_list

    triggers
    |> Enum.map(fn trigger ->
      normalized = %{}

      normalized =
        add_unless_ignored(
          normalized,
          :type,
          get_field(trigger, "type"),
          ignore_list,
          :trigger_type
        )

      normalized =
        add_unless_ignored(
          normalized,
          :enabled,
          get_field(trigger, "enabled"),
          ignore_list,
          :trigger_enabled
        )

      normalized =
        add_unless_ignored(
          normalized,
          :id,
          get_field(trigger, "id"),
          ignore_list,
          :trigger_ids
        )

      normalized =
        add_unless_ignored(
          normalized,
          :cron_expression,
          get_field(trigger, "cron_expression"),
          ignore_list,
          :trigger_cron_expression
        )

      normalized =
        add_unless_ignored(
          normalized,
          :kafka_configuration,
          get_field(trigger, "kafka_configuration"),
          ignore_list,
          :trigger_kafka_configuration
        )

      normalized =
        add_unless_ignored(
          normalized,
          :has_auth_method,
          get_field(trigger, "has_auth_method"),
          ignore_list,
          :trigger_has_auth_method
        )

      normalized =
        add_unless_ignored(
          normalized,
          :comment,
          get_field(trigger, "comment"),
          ignore_list,
          :trigger_comment
        )

      normalized =
        add_unless_ignored(
          normalized,
          :custom_path,
          get_field(trigger, "custom_path"),
          ignore_list,
          :trigger_custom_path
        )

      normalized =
        add_unless_ignored(
          normalized,
          :workflow_id,
          get_field(trigger, "workflow_id"),
          ignore_list,
          :trigger_workflow_id
        )

      normalized =
        add_unless_ignored(
          normalized,
          :inserted_at,
          get_field(trigger, "inserted_at"),
          ignore_list,
          :trigger_inserted_at
        )

      normalized =
        add_unless_ignored(
          normalized,
          :updated_at,
          get_field(trigger, "updated_at"),
          ignore_list,
          :trigger_updated_at
        )

      normalized =
        add_unless_ignored(
          normalized,
          :delete,
          get_field(trigger, "delete"),
          ignore_list,
          :trigger_delete
        )

      normalized =
        add_unless_ignored(
          normalized,
          :errors,
          get_field(trigger, "errors"),
          ignore_list,
          :trigger_errors
        )

      normalized
    end)
    |> Enum.sort_by(fn trigger ->
      if ignoring_ids do
        {trigger[:type], trigger[:enabled]}
      else
        trigger[:id]
      end
    end)
  end

  defp normalize_edges(edges, workflow, ignore_list) do
    ignoring_ids = :edge_ids in ignore_list

    job_id_to_name =
      if ignoring_ids do
        create_job_id_mapping(get_field(workflow, "jobs") || [])
      else
        %{}
      end

    trigger_id_to_index =
      if ignoring_ids do
        create_trigger_id_mapping(get_field(workflow, "triggers") || [])
      else
        %{}
      end

    edges
    |> Enum.map(fn edge ->
      normalized =
        if ignoring_ids do
          source = determine_source(edge, job_id_to_name, trigger_id_to_index)
          target = determine_target(edge, job_id_to_name)

          %{source: source, target: target}
        else
          %{}
          |> add_unless_ignored(
            :id,
            get_field(edge, "id"),
            ignore_list,
            :edge_ids
          )
          |> add_unless_ignored(
            :source_job_id,
            get_field(edge, "source_job_id"),
            ignore_list,
            :edge_ids
          )
          |> add_unless_ignored(
            :source_trigger_id,
            get_field(edge, "source_trigger_id"),
            ignore_list,
            :edge_ids
          )
          |> add_unless_ignored(
            :target_job_id,
            get_field(edge, "target_job_id"),
            ignore_list,
            :edge_ids
          )
        end

      normalized =
        add_unless_ignored(
          normalized,
          :enabled,
          get_field(edge, "enabled"),
          ignore_list,
          :edge_enabled
        )

      normalized =
        add_unless_ignored(
          normalized,
          :condition_type,
          get_field(edge, "condition_type"),
          ignore_list,
          :edge_condition_type
        )

      normalized =
        add_unless_ignored(
          normalized,
          :condition_expression,
          get_field(edge, "condition_expression"),
          ignore_list,
          :edge_condition_expression
        )

      normalized =
        add_unless_ignored(
          normalized,
          :condition_label,
          get_field(edge, "condition_label"),
          ignore_list,
          :edge_condition_label
        )

      normalized =
        add_unless_ignored(
          normalized,
          :workflow_id,
          get_field(edge, "workflow_id"),
          ignore_list,
          :edge_workflow_id
        )

      normalized =
        add_unless_ignored(
          normalized,
          :inserted_at,
          get_field(edge, "inserted_at"),
          ignore_list,
          :edge_inserted_at
        )

      normalized =
        add_unless_ignored(
          normalized,
          :updated_at,
          get_field(edge, "updated_at"),
          ignore_list,
          :edge_updated_at
        )

      normalized =
        add_unless_ignored(
          normalized,
          :delete,
          get_field(edge, "delete"),
          ignore_list,
          :edge_delete
        )

      normalized =
        add_unless_ignored(
          normalized,
          :errors,
          get_field(edge, "errors"),
          ignore_list,
          :edge_errors
        )

      normalized
    end)
    |> Enum.sort_by(fn edge ->
      if ignoring_ids do
        {edge[:source], edge[:target], edge[:condition_type]}
      else
        edge[:id]
      end
    end)
  end

  defp add_unless_ignored(map, key, value, ignore_list, ignore_key \\ nil) do
    check_key = ignore_key || key

    if check_key in ignore_list do
      map
    else
      Map.put(map, key, value)
    end
  end

  defp get_field(nil, _field), do: nil

  defp get_field(data, field) when is_map(data) do
    Map.get(data, field) || Map.get(data, String.to_atom(field))
  end

  defp create_job_id_mapping(jobs) do
    jobs
    |> Enum.reduce(%{}, fn job, acc ->
      Map.put(acc, get_field(job, "id"), get_field(job, "name"))
    end)
  end

  defp create_trigger_id_mapping(triggers) do
    triggers
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {trigger, index}, acc ->
      trigger_type = get_field(trigger, "type")
      Map.put(acc, get_field(trigger, "id"), "trigger_#{trigger_type}_#{index}")
    end)
  end

  defp determine_source(edge, job_id_to_name, trigger_id_to_index) do
    source_job_id = get_field(edge, "source_job_id")
    source_trigger_id = get_field(edge, "source_trigger_id")

    cond do
      source_job_id && source_job_id != nil ->
        {:job, job_id_to_name[source_job_id]}

      source_trigger_id && source_trigger_id != nil ->
        {:trigger, trigger_id_to_index[source_trigger_id]}

      true ->
        {:unknown, nil}
    end
  end

  defp determine_target(edge, job_id_to_name) do
    target_job_id = get_field(edge, "target_job_id")

    if target_job_id && target_job_id != nil do
      {:job, job_id_to_name[target_job_id]}
    else
      {:unknown, nil}
    end
  end
end
