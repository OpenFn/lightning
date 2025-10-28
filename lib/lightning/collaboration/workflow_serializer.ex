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
    concurrency =
      case Yex.Map.fetch(workflow_map, "concurrency") do
        {:ok, value} when is_float(value) -> trunc(value)
        {:ok, nil} -> nil
        :error -> nil
      end

    enable_job_logs =
      case Yex.Map.fetch(workflow_map, "enable_job_logs") do
        {:ok, value} when is_boolean(value) -> value
        :error -> nil
      end

    positions = extract_positions(positions_map)

    # Build the map for save_workflow/2
    %{
      "id" => id,
      "name" => name,
      "concurrency" => concurrency,
      "enable_job_logs" => enable_job_logs,
      "jobs" => extract_jobs(jobs_array),
      "edges" => extract_edges(edges_array),
      "triggers" => extract_triggers(triggers_array),
      "positions" => if(Enum.empty?(positions), do: nil, else: positions)
    }
  end

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
      trigger_map =
        Yex.MapPrelim.from(%{
          "cron_expression" => trigger.cron_expression,
          "enabled" => trigger.enabled,
          "has_auth_method" => trigger.has_auth_method,
          "id" => trigger.id,
          "type" => trigger.type |> to_string()
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
      Map.take(
        trigger,
        ~w(id type enabled cron_expression has_auth_method)
      )
    end)
  end

  defp extract_positions(positions_map) do
    Yex.Map.to_json(positions_map)
  end

  defp extract_text_field(%Yex.Text{} = text) do
    Yex.Text.to_string(text)
  end

  defp extract_text_field(string) when is_binary(string), do: string
  defp extract_text_field(nil), do: ""

  # Convert DateTime to ISO8601 string for Y.Doc storage
  # Y.Doc can't store DateTime structs directly
  defp datetime_to_string(nil), do: nil
  defp datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
