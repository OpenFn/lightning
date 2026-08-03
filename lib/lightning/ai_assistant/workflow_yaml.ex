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

  The YAML is emitted by plain string building (in the same spirit as
  `Lightning.ExportUtils`): multi-line strings such as job bodies become
  block scalars, and anything that cannot be written as a plain or block
  scalar falls back to a JSON-escaped double-quoted scalar, which is valid
  YAML for any string.
  """

  alias Lightning.Workflows.Workflow

  require Logger

  # Bare words YAML would read as booleans or null rather than strings
  @yaml_literals ~w(true false yes no on off null)

  @doc """
  Serializes a workflow to a YAML string matching the client-produced spec.

  Accepts a `%Workflow{}` with `:jobs`, `:triggers` and `:edges` preloaded,
  or a string-keyed workflow state map (as deserialized from a Y.Doc).

  Returns `nil` if serialization fails, mirroring `serializeWorkflowToYAML`
  returning `undefined` on error.
  """
  @spec serialize(Workflow.t() | map()) :: String.t() | nil
  def serialize(%Workflow{} = workflow) do
    workflow |> to_state() |> serialize()
  end

  def serialize(%{} = state) do
    state
    |> spec_pairs()
    |> to_yaml("")
    |> Kernel.<>("\n")
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

  # Builds the spec as nested {key, value} pair lists (order preserved,
  # matching the client's key order).

  defp spec_pairs(state) do
    positions = state["positions"] || %{}
    jobs = state["jobs"] || []
    triggers = state["triggers"] || []
    edges = state["edges"] || []

    [
      {"id", state["id"]},
      {"name", state["name"]},
      {"jobs",
       Enum.map(jobs, fn job ->
         {hyphenate(job["name"]), job_pairs(job, positions)}
       end)},
      {"triggers",
       Enum.map(triggers, fn trigger ->
         {trigger["type"], trigger_pairs(trigger, jobs, positions)}
       end)},
      {"edges", Enum.map(edges, fn edge -> edge_pairs(edge, triggers, jobs) end)}
    ]
  end

  defp job_pairs(job, positions) do
    [
      {"id", job["id"]},
      {"name", job["name"]},
      {"adaptor", job["adaptor"]},
      {"body", job["body"]}
    ] ++ pos_pairs(positions, job["id"])
  end

  defp trigger_pairs(trigger, jobs, positions) do
    type = trigger["type"]

    # The client omits positions for kafka triggers
    pos = if type == "kafka", do: [], else: pos_pairs(positions, trigger["id"])

    [
      {"id", trigger["id"]},
      {"type", type},
      {"enabled", trigger["enabled"]}
    ] ++ pos ++ type_specific_pairs(trigger, jobs)
  end

  defp type_specific_pairs(%{"type" => "cron"} = trigger, jobs) do
    cursor_job =
      trigger["cron_cursor_job_id"] &&
        Enum.find(jobs, &(&1["id"] == trigger["cron_cursor_job_id"]))

    [
      {"cron_expression", trigger["cron_expression"]},
      {"cron_cursor_job", cursor_job && hyphenate(cursor_job["name"])}
    ]
  end

  defp type_specific_pairs(%{"type" => "webhook"} = trigger, _jobs) do
    [{"webhook_reply", trigger["webhook_reply"]}] ++
      webhook_response_config_pairs(trigger["webhook_response_config"])
  end

  defp type_specific_pairs(_trigger, _jobs), do: []

  defp webhook_response_config_pairs(%{} = config) do
    codes =
      [
        {"success_code", config["success_code"]},
        {"error_code", config["error_code"]}
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    if codes == [], do: [], else: [{"webhook_response_config", codes}]
  end

  defp webhook_response_config_pairs(_config), do: []

  defp edge_pairs(edge, triggers, jobs) do
    source_trigger =
      edge["source_trigger_id"] &&
        Enum.find(triggers, &(&1["id"] == edge["source_trigger_id"]))

    source_job =
      edge["source_job_id"] &&
        Enum.find(jobs, &(&1["id"] == edge["source_job_id"]))

    target_job = Enum.find(jobs, &(&1["id"] == edge["target_job_id"]))

    source_name =
      (source_trigger && source_trigger["type"]) ||
        (source_job && hyphenate(source_job["name"]))

    target_name = (target_job && hyphenate(target_job["name"])) || ""

    pairs =
      [
        {"id", edge["id"]},
        {"condition_type", presence(edge["condition_type"]) || "always"},
        {"enabled", edge["enabled"] != false},
        {"target_job", target_name}
      ] ++
        maybe_pair("source_trigger", source_trigger && source_trigger["type"]) ++
        maybe_pair("source_job", source_job && hyphenate(source_job["name"])) ++
        maybe_pair("condition_label", presence(edge["condition_label"])) ++
        maybe_pair(
          "condition_expression",
          presence(edge["condition_expression"])
        )

    {"#{source_name}->#{target_name}", pairs}
  end

  defp pos_pairs(positions, id) do
    case positions[id] do
      %{"x" => x, "y" => y} when is_number(x) and is_number(y) ->
        [{"pos", [{"x", round(x)}, {"y", round(y)}]}]

      _ ->
        []
    end
  end

  defp maybe_pair(_key, nil), do: []
  defp maybe_pair(key, value), do: [{key, value}]

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  defp hyphenate(string) when is_binary(string),
    do: String.replace(string, ~r/\s+/, "-")

  defp hyphenate(other), do: other

  # YAML emission — plain string building over the ordered pair lists.

  defp to_yaml(pairs, indent) when is_list(pairs) do
    Enum.map_join(pairs, "\n", fn {key, value} ->
      emit_pair(key, value, indent)
    end)
  end

  defp emit_pair(key, [], indent), do: "#{indent}#{yaml_key(key)}: {}"

  defp emit_pair(key, pairs, indent) when is_list(pairs) do
    "#{indent}#{yaml_key(key)}:\n" <> to_yaml(pairs, indent <> "  ")
  end

  defp emit_pair(key, value, indent) when is_binary(value) do
    if String.contains?(value, "\n") do
      emit_multiline(key, value, indent)
    else
      "#{indent}#{yaml_key(key)}: #{yaml_scalar(value)}"
    end
  end

  defp emit_pair(key, value, indent),
    do: "#{indent}#{yaml_key(key)}: #{yaml_scalar(value)}"

  # Multi-line strings (job bodies, condition expressions) become block
  # scalars when the content allows it; otherwise fall back to a
  # JSON-escaped double-quoted scalar (valid YAML for any string).
  defp emit_multiline(key, value, indent) do
    cond do
      not block_scalar_safe?(value) ->
        "#{indent}#{yaml_key(key)}: #{Jason.encode!(value)}"

      String.ends_with?(value, "\n") and not String.ends_with?(value, "\n\n") ->
        # "|" (clip) keeps exactly the one trailing newline
        block_scalar(key, "|", String.trim_trailing(value, "\n"), indent)

      not String.ends_with?(value, "\n") ->
        # "|-" (strip) for content without a trailing newline
        block_scalar(key, "|-", value, indent)

      true ->
        # Multiple trailing newlines don't round-trip through clip/strip
        "#{indent}#{yaml_key(key)}: #{Jason.encode!(value)}"
    end
  end

  defp block_scalar(key, header, content, indent) do
    lines =
      content
      |> String.split("\n")
      |> Enum.map_join("\n", fn
        "" -> ""
        line -> "#{indent}  #{line}"
      end)

    "#{indent}#{yaml_key(key)}: #{header}\n#{lines}"
  end

  # Block scalar indentation is auto-detected from the first content line,
  # so the content is only safe when that line exists and carries no leading
  # whitespace of its own.
  defp block_scalar_safe?(value) do
    case String.split(value, "\n", parts: 2) do
      [first, _rest] ->
        first != "" and not String.starts_with?(first, [" ", "\t"])

      _ ->
        false
    end
  end

  defp yaml_key(key) do
    if plain_scalar?(key), do: key, else: Jason.encode!(key)
  end

  defp yaml_scalar(nil), do: "null"
  defp yaml_scalar(true), do: "true"
  defp yaml_scalar(false), do: "false"
  defp yaml_scalar(value) when is_number(value), do: to_string(value)

  defp yaml_scalar(value) when is_binary(value) do
    if plain_scalar?(value), do: value, else: Jason.encode!(value)
  end

  # A string can be written unquoted when it starts with a letter, ends with
  # a letter or digit, only contains unambiguous characters, and isn't a
  # bare word YAML would read as a boolean or null.
  defp plain_scalar?(value) when is_binary(value) do
    Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_\-@\.\/> ]*[a-zA-Z0-9]$/, value) and
      String.downcase(value) not in @yaml_literals
  end

  defp plain_scalar?(_value), do: false
end
