defmodule Lightning.AiAssistant.WorkflowYAML do
  @moduledoc """
  Serializes a workflow into the YAML "spec" shape the AI assistant sends to
  Apollo as `workflow_yaml`.

  This mirrors the client-side serialization in
  `assets/js/collaborative-editor/utils/workflowSerialization.ts`
  (`prepareWorkflowForSerialization` + `serializeWorkflowToYAML`, which
  delegate to `convertWorkflowStateToSpec` in `assets/js/yaml/util.ts` with
  `includeIds: true`). Apollo parses this YAML, so the two implementations
  must stay in sync: same top-level keys (`id`, `name`, `jobs`, `triggers`,
  `edges`), same per-node fields, and nodes keyed by hyphenated name (jobs),
  trigger type (triggers) and `source->target` (edges).

  It is used to build workflow context server-side when a global chat message
  arrives without workflow YAML from the client (e.g. the workflow store had
  not hydrated yet). It accepts either:

  - a saved `%Workflow{}` (with jobs, triggers and edges preloaded), or
  - the string-keyed workflow state map produced by
    `Lightning.Collaboration.WorkflowSerializer.deserialize_from_ydoc/2`,
    which includes unsaved collaborative edits.
  """

  alias Lightning.Workflows.Workflow

  require Logger

  @doc """
  Serializes a workflow to a YAML string matching the client-produced spec.

  Accepts a `%Workflow{}` with `:jobs`, `:triggers` and `:edges` preloaded,
  or a string-keyed workflow state map (as deserialized from a Y.Doc).

  Returns `nil` if encoding fails, mirroring `serializeWorkflowToYAML`
  returning `undefined` on error.
  """
  @spec serialize(Workflow.t() | map()) :: String.t() | nil
  def serialize(%Workflow{} = workflow) do
    workflow |> to_state() |> serialize()
  end

  def serialize(%{} = state) do
    positions = state["positions"] || %{}
    jobs = state["jobs"] || []
    triggers = state["triggers"] || []
    edges = state["edges"] || []

    %{
      "id" => state["id"],
      "name" => state["name"],
      "jobs" => jobs_spec(jobs, positions),
      "triggers" => triggers_spec(triggers, jobs, positions),
      "edges" => edges_spec(edges, triggers, jobs)
    }
    |> Ymlr.document!()
    |> String.trim_leading("---\n")
  rescue
    error ->
      Logger.error(
        "[AI Assistant] Failed to serialize workflow #{inspect(state["id"])} " <>
          "to YAML: #{Exception.message(error)}"
      )

      nil
  end

  # Converts a saved workflow struct into the same string-keyed state shape
  # that WorkflowSerializer.deserialize_from_ydoc/2 produces, so both sources
  # flow through the same spec builder.
  defp to_state(%Workflow{} = workflow) do
    %{
      "id" => workflow.id,
      "name" => workflow.name,
      "positions" => workflow.positions,
      "jobs" =>
        Enum.map(workflow.jobs, fn job ->
          %{
            "id" => job.id,
            "name" => job.name,
            "adaptor" => job.adaptor,
            "body" => job.body
          }
        end),
      "triggers" =>
        Enum.map(workflow.triggers, fn trigger ->
          %{
            "id" => trigger.id,
            "type" => to_string(trigger.type),
            "enabled" => trigger.enabled,
            "cron_expression" => trigger.cron_expression,
            "cron_cursor_job_id" => trigger.cron_cursor_job_id,
            "webhook_reply" =>
              trigger.webhook_reply && to_string(trigger.webhook_reply),
            "webhook_response_config" =>
              case trigger.webhook_response_config do
                nil ->
                  nil

                config ->
                  %{
                    "success_code" => config.success_code,
                    "error_code" => config.error_code
                  }
              end
          }
        end),
      "edges" =>
        Enum.map(workflow.edges, fn edge ->
          %{
            "id" => edge.id,
            "condition_type" =>
              edge.condition_type && to_string(edge.condition_type),
            "condition_label" => edge.condition_label,
            "condition_expression" => edge.condition_expression,
            "enabled" => edge.enabled,
            "source_job_id" => edge.source_job_id,
            "source_trigger_id" => edge.source_trigger_id,
            "target_job_id" => edge.target_job_id
          }
        end)
    }
  end

  defp jobs_spec(jobs, positions) do
    Map.new(jobs, fn job ->
      details =
        %{
          "id" => job["id"],
          "name" => job["name"],
          "adaptor" => job["adaptor"],
          "body" => job["body"]
        }
        |> maybe_put_pos(positions, job["id"])

      {hyphenate(job["name"]), details}
    end)
  end

  defp triggers_spec(triggers, jobs, positions) do
    Map.new(triggers, fn trigger ->
      type = trigger["type"]

      details =
        %{
          "id" => trigger["id"],
          "type" => type,
          "enabled" => trigger["enabled"]
        }
        |> then(fn details ->
          # The client omits positions for kafka triggers
          if type == "kafka" do
            details
          else
            maybe_put_pos(details, positions, trigger["id"])
          end
        end)
        |> put_type_specific_fields(trigger, jobs)

      {type, details}
    end)
  end

  defp put_type_specific_fields(details, %{"type" => "cron"} = trigger, jobs) do
    cursor_job =
      trigger["cron_cursor_job_id"] &&
        Enum.find(jobs, &(&1["id"] == trigger["cron_cursor_job_id"]))

    details
    |> Map.put("cron_expression", trigger["cron_expression"])
    |> Map.put("cron_cursor_job", cursor_job && hyphenate(cursor_job["name"]))
  end

  defp put_type_specific_fields(
         details,
         %{"type" => "webhook"} = trigger,
         _jobs
       ) do
    details
    |> Map.put("webhook_reply", trigger["webhook_reply"])
    |> put_webhook_response_config(trigger["webhook_response_config"])
  end

  defp put_type_specific_fields(details, _trigger, _jobs), do: details

  defp put_webhook_response_config(details, %{} = config) do
    codes =
      %{
        "success_code" => config["success_code"],
        "error_code" => config["error_code"]
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    if map_size(codes) > 0 do
      Map.put(details, "webhook_response_config", codes)
    else
      details
    end
  end

  defp put_webhook_response_config(details, _config), do: details

  defp edges_spec(edges, triggers, jobs) do
    Map.new(edges, fn edge ->
      source_trigger =
        edge["source_trigger_id"] &&
          Enum.find(triggers, &(&1["id"] == edge["source_trigger_id"]))

      source_job =
        edge["source_job_id"] &&
          Enum.find(jobs, &(&1["id"] == edge["source_job_id"]))

      target_job = Enum.find(jobs, &(&1["id"] == edge["target_job_id"]))

      details =
        %{
          "id" => edge["id"],
          "condition_type" => presence(edge["condition_type"]) || "always",
          "enabled" => edge["enabled"] != false,
          "target_job" => (target_job && hyphenate(target_job["name"])) || ""
        }
        |> maybe_put("source_trigger", source_trigger && source_trigger["type"])
        |> maybe_put("source_job", source_job && hyphenate(source_job["name"]))
        |> maybe_put("condition_label", presence(edge["condition_label"]))
        |> maybe_put(
          "condition_expression",
          presence(edge["condition_expression"])
        )

      source_name = details["source_trigger"] || details["source_job"]

      {"#{source_name}->#{details["target_job"]}", details}
    end)
  end

  defp maybe_put_pos(details, positions, id) do
    case positions[id] do
      %{"x" => x, "y" => y} when is_number(x) and is_number(y) ->
        Map.put(details, "pos", %{"x" => round(x), "y" => round(y)})

      _ ->
        details
    end
  end

  defp maybe_put(details, _key, nil), do: details
  defp maybe_put(details, key, value), do: Map.put(details, key, value)

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  defp hyphenate(string) when is_binary(string),
    do: String.replace(string, ~r/\s+/, "-")

  defp hyphenate(other), do: other
end
