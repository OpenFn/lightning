defmodule Lightning.Collaboration.WorkflowSerializer do
  @moduledoc """
  Serializes Lightning Workflow structs to/from Y.Doc CRDT documents.

  This module handles bidirectional conversion:
  - `serialize_to_ydoc/2` - Write workflow data into a Y.Doc (workflow → Y.Doc)
  - `deserialize_from_ydoc/2` - Extract workflow data from a Y.Doc (Y.Doc → workflow)

  These functions maintain consistent field mappings between the two formats.

  ## Y.Doc Structure

  The Y.Doc contains six top-level collections:

  - `workflow` (Map): Core workflow metadata (id, name, lock_version,
    deleted_at, concurrency, enable_job_logs)
  - `jobs` (Array): Array of job objects with Y.Text body field
  - `edges` (Array): Array of edge objects connecting jobs/triggers
  - `triggers` (Array): Array of trigger objects (webhook, cron, kafka)
  - `positions` (Map): Canvas positions for visual editor (node_id → {x, y})
  - `errors` (Map): Field-level validation errors (field_path → error_message)

  ## Field Mappings

  ### Special Type Conversions

  - Job `body`: Stored as Y.Text (for collaborative editing)
  - Atoms (condition_type, trigger type): Converted to/from strings
  - Nil values: Coalesced to empty strings or defaults where appropriate
  """

  alias Lightning.Workflows.Triggers.KafkaConfiguration
  alias Lightning.Workflows.Workflow

  @doc """
  Writes a workflow's data into a Y.Doc.

  This initializes the Y.Doc structure with:
  - `workflow` map: Core workflow metadata (id, name, lock_version, deleted_at,
    concurrency, enable_job_logs)
  - `jobs` array: Array of job objects
  - `edges` array: Array of edge objects
  - `triggers` array: Array of trigger objects
  - `positions` map: Canvas positions for visual editor

  This function is a refactored version of Session.initialize_workflow_data/2
  with no behavioral changes.

  ## Parameters
  - `doc`: The Y.Doc to write into
  - `workflow`: The workflow struct to serialize

  ## Returns
  - The doc (for chaining convenience)
  """
  @spec serialize_to_ydoc(Yex.Doc.t(), Workflow.t()) :: Yex.Doc.t()
  def serialize_to_ydoc(doc, workflow) do
    # Get Yex objects BEFORE transaction to avoid hanging the VM
    workflow_map = Yex.Doc.get_map(doc, "workflow")
    jobs_array = Yex.Doc.get_array(doc, "jobs")
    edges_array = Yex.Doc.get_array(doc, "edges")
    triggers_array = Yex.Doc.get_array(doc, "triggers")
    positions = Yex.Doc.get_map(doc, "positions")
    errors = Yex.Doc.get_map(doc, "errors")

    Yex.Doc.transaction(doc, "initialize_workflow_document", fn ->
      # Set workflow properties
      Yex.Map.set(workflow_map, "id", workflow.id)
      Yex.Map.set(workflow_map, "name", workflow.name || "")
      Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)

      Yex.Map.set(
        workflow_map,
        "deleted_at",
        datetime_to_string(workflow.deleted_at)
      )

      Yex.Map.set(workflow_map, "concurrency", workflow.concurrency)
      Yex.Map.set(workflow_map, "enable_job_logs", workflow.enable_job_logs)

      initialize_jobs(jobs_array, workflow.jobs)
      initialize_edges(edges_array, workflow.edges)
      initialize_triggers(triggers_array, workflow.triggers)
      initialize_positions(positions, workflow.positions)

      # Initialize empty errors map (no errors on fresh load)
      # Note: We don't set individual keys here, just ensure the map exists
      # Keys will be added by validation error writing logic
      _errors_initialized = errors
    end)

    doc
  end

  @doc """
  Extracts workflow data from a Y.Doc.

  This reads the Y.Doc structure and converts it to a map suitable for
  passing to Lightning.Workflows.save_workflow/2.

  ## Parameters
  - `doc`: The Y.Doc to read from
  - `workflow_id`: The workflow ID (needed for the returned map)

  ## Returns
  - A map with workflow data in the format expected by Workflows.save_workflow/2
  """
  @spec deserialize_from_ydoc(Yex.Doc.t(), String.t()) :: map()
  def deserialize_from_ydoc(doc, _workflow_id) do
    # Get the five Y.Doc collections
    workflow_map = Yex.Doc.get_map(doc, "workflow")
    jobs_array = Yex.Doc.get_array(doc, "jobs")
    edges_array = Yex.Doc.get_array(doc, "edges")
    triggers_array = Yex.Doc.get_array(doc, "triggers")
    positions_map = Yex.Doc.get_map(doc, "positions")

    # Extract workflow metadata
    id = Yex.Map.fetch!(workflow_map, "id")
    name = Yex.Map.fetch!(workflow_map, "name")

    # Y.js numbers are floats - convert to integer for database
    # Use :not_found sentinel to distinguish missing fields from explicit nil
    concurrency =
      case Yex.Map.fetch(workflow_map, "concurrency") do
        {:ok, value} when is_float(value) -> trunc(value)
        {:ok, nil} -> nil
        :error -> :not_found
      end

    enable_job_logs =
      case Yex.Map.fetch(workflow_map, "enable_job_logs") do
        {:ok, value} when is_boolean(value) -> value
        {:ok, nil} -> nil
        :error -> :not_found
      end

    positions = extract_positions(positions_map)

    # Build the base map for save_workflow/2
    base_map = %{
      "id" => id,
      "name" => name,
      "jobs" => extract_jobs(jobs_array),
      "edges" => extract_edges(edges_array),
      "triggers" => extract_triggers(triggers_array),
      "positions" => if(Enum.empty?(positions), do: nil, else: positions)
    }

    # Add optional fields only if they were present in Y.Doc
    # This allows schema defaults to apply for old documents while
    # preserving explicit nil values in new documents
    base_map
    |> maybe_put_field("concurrency", concurrency)
    |> maybe_put_field("enable_job_logs", enable_job_logs)
  end

  # Convert DateTime to ISO8601 string for Y.Doc storage
  # Y.Doc can't store DateTime structs directly
  def datetime_to_string(nil), do: nil
  def datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  # Private helper functions

  defp initialize_jobs(jobs_array, jobs) do
    Enum.each(jobs || [], fn job ->
      job_map =
        Yex.MapPrelim.from(%{
          "id" => job.id,
          "name" => job.name || "",
          "body" => Yex.TextPrelim.from(job.body || ""),
          "adaptor" => job.adaptor,
          "project_credential_id" => job.project_credential_id,
          "keychain_credential_id" => job.keychain_credential_id
        })

      Yex.Array.push(jobs_array, job_map)
    end)
  end

  defp initialize_edges(edges_array, edges) do
    Enum.each(edges || [], fn edge ->
      edge_map =
        Yex.MapPrelim.from(%{
          "condition_expression" => edge.condition_expression,
          "condition_label" => edge.condition_label,
          "condition_type" => edge.condition_type |> to_string(),
          "enabled" => edge.enabled,
          # "errors" => edge.errors,
          "id" => edge.id,
          "source_job_id" => edge.source_job_id,
          "source_trigger_id" => edge.source_trigger_id,
          "target_job_id" => edge.target_job_id
        })

      Yex.Array.push(edges_array, edge_map)
    end)
  end

  defp initialize_triggers(triggers_array, triggers) do
    Enum.each(triggers || [], fn trigger ->
      kafka_configuration =
        trigger.kafka_configuration &&
          Yex.MapPrelim.from(%{
            "connect_timeout" => trigger.kafka_configuration.connect_timeout,
            "group_id" => trigger.kafka_configuration.group_id,
            "hosts_string" =>
              KafkaConfiguration.generate_hosts_string(
                trigger.kafka_configuration.hosts
              ),
            "initial_offset_reset_policy" =>
              trigger.kafka_configuration.initial_offset_reset_policy,
            "password" => trigger.kafka_configuration.password,
            "sasl" => to_string(trigger.kafka_configuration.sasl),
            "ssl" => trigger.kafka_configuration.ssl,
            "topics_string" =>
              KafkaConfiguration.generate_topics_string(
                trigger.kafka_configuration.topics
              ),
            "username" => trigger.kafka_configuration.username
          })

      trigger_map =
        Yex.MapPrelim.from(%{
          "kafka_configuration" => kafka_configuration,
          "cron_expression" => trigger.cron_expression,
          "enabled" => trigger.enabled,
          "id" => trigger.id,
          "type" => trigger.type |> to_string(),
          "webhook_reply" => trigger.webhook_reply |> to_string()
        })

      Yex.Array.push(triggers_array, trigger_map)
    end)
  end

  defp initialize_positions(positions, workflow_positions) do
    Enum.each(workflow_positions || [], fn {id, position} ->
      Yex.Map.set(positions, id, position)
    end)
  end

  # Deserialization helper functions

  defp extract_jobs(jobs_array) do
    jobs_array
    |> Yex.Array.to_json()
    |> Enum.map(fn job ->
      %{
        "id" => job["id"],
        "name" => job["name"],
        "body" => extract_text_field(job["body"]),
        "adaptor" => job["adaptor"],
        "project_credential_id" => job["project_credential_id"],
        "keychain_credential_id" => job["keychain_credential_id"]
      }
    end)
  end

  defp extract_edges(edges_array) do
    edges_array
    |> Yex.Array.to_json()
    |> Enum.map(fn edge ->
      edge
      |> Map.take(~w(id source_trigger_id source_job_id target_job_id
          condition_type condition_expression condition_label enabled))
    end)
  end

  defp extract_triggers(triggers_array) do
    triggers_array
    |> Yex.Array.to_json()
    |> Enum.map(fn trigger ->
      trigger
      |> Map.take(~w(id type enabled cron_expression webhook_reply kafka_configuration))
      |> normalize_kafka_configuration()
    end)
  end

  # Y.Doc serializes numbers as floats, but connect_timeout must be an integer
  defp normalize_kafka_configuration(
         %{"kafka_configuration" => %{} = kafka_config} = trigger
       ) do
    connect_timeout =
      case Map.fetch(kafka_config, "connect_timeout") do
        {:ok, value} when is_float(value) -> trunc(value)
        {:ok, nil} -> nil
        :error -> :not_found
      end

    normalized_config =
      maybe_put_field(kafka_config, "connect_timeout", connect_timeout)

    Map.put(trigger, "kafka_configuration", normalized_config)
  end

  defp normalize_kafka_configuration(trigger), do: trigger

  defp extract_positions(positions_map) do
    Yex.Map.to_json(positions_map)
  end

  defp extract_text_field(%Yex.Text{} = text) do
    Yex.Text.to_string(text)
  end

  defp extract_text_field(string) when is_binary(string), do: string
  defp extract_text_field(nil), do: ""

  # Catch-all for unexpected types - log and return empty string
  defp extract_text_field(value) do
    require Logger

    Logger.warning(
      "extract_text_field received unexpected type: #{inspect(value)}"
    )

    ""
  end

  # Helper to conditionally add a field to a map
  # Only adds the field if value is not :not_found (i.e., field existed in Y.Doc)
  # This allows schema defaults to apply for truly missing fields
  defp maybe_put_field(map, _key, :not_found), do: map
  defp maybe_put_field(map, key, value), do: Map.put(map, key, value)
end
