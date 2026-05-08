defmodule Lightning.Workflows.YamlFormat.V2 do
  @moduledoc """
  v2 (CLI-aligned) YAML format for Lightning workflows.

  See `test/fixtures/portability/v2/canonical_workflow.yaml` for the
  spec-by-example. New contributors should read that file before this module.

  ## Authoritative source: @openfn/cli

  The v2 spec is a draft (`docs#774`); the `@openfn/cli` parser is the
  authoritative source. The structural decisions below come directly from:

  - <https://raw.githubusercontent.com/OpenFn/kit/main/packages/lexicon/core.d.ts>
  - <https://raw.githubusercontent.com/OpenFn/kit/main/packages/project/src/serialize/to-fs.ts>
  - <https://raw.githubusercontent.com/OpenFn/kit/main/packages/project/src/parse/from-app-state.ts>
  - <https://raw.githubusercontent.com/OpenFn/kit/main/packages/project/src/serialize/to-app-state.ts>
  - <https://raw.githubusercontent.com/OpenFn/kit/main/packages/project/test/fixtures/sample-v2-project.ts>

  ## Shape

  Workflow on the wire (YAML):

      name: <string>
      steps: [<step>, ...]      # one array — both jobs and triggers

  After `parse_workflow/1`, the canonical map splits that single `steps:`
  array into two sibling keys — `:triggers` and `:steps` — so callers can
  iterate triggers and jobs separately without re-checking discriminators.
  Both keys are always present in the canonical map (empty list when the
  input had none of that kind).

  A **trigger step** has a `type` discriminator (`webhook` / `cron` / `kafka`):

      - id: <string>
        type: webhook | cron | kafka
        enabled: true | false
        openfn:
          # Lightning-specific runtime config goes here:
          cron: "0 0 * * *"                   # cron only
          cron_cursor: <step-id>              # cron only
          webhook_reply: before_start | ...   # webhook only
          kafka:                              # kafka only
            hosts: [["broker", 9092]]
            topics: [...]
            initial_offset_reset_policy: latest
            connect_timeout: 30
        next: <step-id>                       # collapsed when single :always
        # OR
        next:
          <step-id>:
            condition: always                 # object form when 2+ targets

  A **job step** has no `type` field:

      - id: <string>
        name: <string>
        adaptor: <string>
        expression: |
          fn(state => state)
        configuration: <credential-key>      # optional
        next:
          <step-id>:
            condition: always | on_job_success | on_job_failure | js_expression
            expression: |                    # only when condition: js_expression
              <js body>
            label: <string>                  # optional
            disabled: true                    # optional, defaults to false

  ## Condition discrimination

  Standard literals — `always`, `never`, `on_job_success`, `on_job_failure` —
  emit on a single line. The fifth literal `js_expression` opts in to a
  sibling `expression:` block carrying the JS body. The CLI's `to-app-state.ts`
  treats anything else found in `condition:` as a bare JS expression body for
  backwards compatibility; the parser preserves it verbatim.

  ## Field-name table

  | concept                        | v2 field name                |
  |--------------------------------|------------------------------|
  | workflow steps array (YAML)    | `steps:` (jobs + triggers)   |
  | canonical triggers list        | `:triggers` (parser output)  |
  | canonical jobs list            | `:steps` (parser output)     |
  | trigger discriminator          | `type:`                      |
  | trigger enabled                | `enabled:`                   |
  | step expression / body         | `expression:`                |
  | step adaptor                   | `adaptor:`                   |
  | step credential                | `configuration:`             |
  | trigger Lightning-only state   | nested under `openfn:`       |
  | cron expression                | `cron:` (under `openfn:`)    |
  | kafka block                    | `kafka:` (under `openfn:`)   |
  | outgoing edges from a node     | `next:` (string or object)   |
  | edge condition                 | `condition:`                 |
  | edge js body                   | `expression:`                |
  | edge label                     | `label:`                     |
  | edge disabled (inverted)       | `disabled:`                  |

  Project-level v2 (`serialize_project/2`, `parse_project/1`) is fully
  implemented; the module is the single source of truth for both workflow-
  and project-level v2 YAML.
  """

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Workflow

  require Logger

  @field_names_provisional true

  @doc """
  Whether the v2 field names emitted by this module should be considered
  provisional. The structural choices above are confirmed against `@openfn/cli`
  source; the flag remains `true` until the broader `docs#774` portability spec
  is finalised.
  """
  @spec field_names_provisional?() :: boolean()
  def field_names_provisional?, do: @field_names_provisional

  # The standard edge condition literals understood by `@openfn/cli`. Anything
  # not in this list, when found in `condition:`, is treated as a JS expression
  # body (per `to-app-state.ts`).
  @standard_condition_literals ~w(always never on_job_success on_job_failure)

  # Authoritative public field lists for the workflow-level v2 shape. The
  # `coverage` test in test/lightning/workflows/yaml_format_v2_test.exs walks
  # these against test/fixtures/portability/v2/canonical_workflow.yaml; if a
  # field listed here never appears in the canonical fixture, that test fails.
  #
  # The parser splits the YAML's combined `steps:` array into two lists in the
  # canonical map — `:triggers` (records carrying a `type:` discriminator) and
  # `:steps` (job records). Both keys are always present (empty list when the
  # input contained none of that kind).
  @v2_workflow_fields [
    :name,
    :triggers,
    :steps
  ]

  # Authoritative public field list for the project-level v2 shape. Mirror of
  # @v2_workflow_fields. The `coverage` test in
  # test/lightning/workflows/yaml_format_project_v2_test.exs walks these
  # against test/fixtures/portability/v2/canonical_project.yaml; if a field
  # listed here never appears in the canonical fixture, that test fails.
  @v2_project_fields [
    :name,
    :description,
    :collections,
    :credentials,
    :workflows,
    :openfn
  ]

  # Per-step common fields (apply to both triggers and jobs).
  @v2_step_common_fields [
    :id,
    :enabled,
    :next
  ]

  # Per-trigger fields (the type discriminator + Lightning-specific openfn
  # blob carrying cron / kafka / webhook config).
  @v2_trigger_fields [
    :id,
    :type,
    :enabled,
    :openfn,
    :next
  ]

  # Per-step (job) fields. Jobs have no `type:` discriminator. `:steps` in
  # the canonical map after parsing is the JOB list — triggers split out
  # into the sibling `:triggers` key.
  @v2_step_fields [
    :id,
    :name,
    :adaptor,
    :expression,
    :configuration,
    :next
  ]

  # Per-edge (`next:` map value) v2 field names. The `:expression` key carries
  # a JS expression body when `:condition` is the literal `"js_expression"`.
  @v2_edge_fields [
    :condition,
    :expression,
    :label,
    :disabled
  ]

  # Lightning-specific keys that live inside a trigger step's `openfn:` blob.
  # These don't exist in the CLI lexicon and are namespaced here so the CLI
  # round-trips them as opaque metadata. The internal canonical keys match the
  # YAML keys 1:1: `cron:`, `cron_cursor:`, `webhook_reply:`, `kafka:`.
  @openfn_trigger_keys [
    :cron,
    :cron_cursor,
    :webhook_reply,
    :kafka
  ]

  # Kafka configuration sub-fields. Aligns with Lightning's
  # `Triggers.KafkaConfiguration` schema (the standard four plus optional
  # SASL/SSL credentials).
  @kafka_config_fields [
    :hosts,
    :topics,
    :initial_offset_reset_policy,
    :connect_timeout,
    :group_id,
    :sasl,
    :ssl,
    :username,
    :password
  ]

  @doc """
  The list of public fields the v2 workflow spec emits at workflow level.

  Used by the canonical-fixture coverage test to detect drift between this
  module and `test/fixtures/portability/v2/canonical_workflow.yaml`.
  """
  @spec v2_workflow_fields() :: [atom()]
  def v2_workflow_fields, do: @v2_workflow_fields

  @doc """
  The list of public fields the v2 project spec emits at project level.

  Used by the canonical-fixture coverage test to detect drift between this
  module and `test/fixtures/portability/v2/canonical_project.yaml`.
  """
  @spec v2_project_fields() :: [atom()]
  def v2_project_fields, do: @v2_project_fields

  @doc "Common fields present on every step (trigger or job)."
  @spec v2_step_common_fields() :: [atom()]
  def v2_step_common_fields, do: @v2_step_common_fields

  @doc "Per-trigger v2 field names."
  @spec v2_trigger_fields() :: [atom()]
  def v2_trigger_fields, do: @v2_trigger_fields

  @doc "Per-step (job) v2 field names."
  @spec v2_step_fields() :: [atom()]
  def v2_step_fields, do: @v2_step_fields

  @doc "Per-edge (`next:` map value) v2 field names."
  @spec v2_edge_fields() :: [atom()]
  def v2_edge_fields, do: @v2_edge_fields

  @doc "Keys that live under a trigger step's `openfn:` blob."
  @spec openfn_trigger_keys() :: [atom()]
  def openfn_trigger_keys, do: @openfn_trigger_keys

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Serialize a workflow struct to v2 YAML.

  Expects `workflow.jobs`, `workflow.triggers`, `workflow.edges` to be loaded.
  """
  @spec serialize_workflow(Workflow.t()) :: {:ok, binary()} | {:error, term()}
  def serialize_workflow(%Workflow{} = workflow) do
    canonical = workflow_struct_to_canonical(workflow)
    {:ok, emit(canonical)}
  rescue
    err -> {:error, {:serialize_failed, err}}
  end

  def serialize_workflow(_), do: {:error, :not_a_workflow}

  @doc """
  Serialize a project to v2 YAML.

  Produces a stateless project document — no UUIDs in the body. Stable
  hyphenated names are the join keys. The optional trailing `openfn:` block
  carries runtime info (`project_id`, `endpoint`) per kit#1398.

  The `snapshots` argument is accepted for façade-compatibility with the v1
  serializer but is not used for v2 (v2 always emits the project's current
  workflow set).

  Expects the project to have its associations preloaded; if not, this
  function preloads them itself.
  """
  @spec serialize_project(Project.t(), [any()] | nil) ::
          {:ok, binary()} | {:error, term()}
  def serialize_project(project, snapshots \\ nil)

  def serialize_project(%Project{} = project, snapshots) do
    canonical = project_struct_to_canonical(project, snapshots)
    {:ok, emit_project(canonical)}
  rescue
    err -> {:error, {:serialize_failed, err}}
  end

  def serialize_project(_, _), do: {:error, :not_a_project}

  @doc """
  Parse a v2 workflow document.

  Accepts either a YAML string or a pre-parsed map (so callers can dispatch on
  `detect_format/1` without re-parsing). Returns the canonical workflow map
  used by `serialize_workflow/1` on round-trip.
  """
  @spec parse_workflow(binary() | map()) :: {:ok, map()} | {:error, term()}
  def parse_workflow(yaml_string) when is_binary(yaml_string) do
    with {:ok, parsed} <- decode(yaml_string) do
      parse_workflow(parsed)
    end
  end

  def parse_workflow(%{} = parsed) do
    parse_workflow_map(parsed)
  end

  def parse_workflow(_), do: {:error, :invalid_input}

  @doc """
  Parse a v2 project document.

  Accepts either a YAML string or a pre-parsed map. Returns a canonical map
  with stable shape:

      %{
        name: <string | nil>,
        description: <string | nil>,
        collections: [%{name: <string>, description: <string | nil>}, ...],
        credentials: [%{name: <string>, schema: <string | nil>}, ...],
        workflows: [<canonical workflow map> | ...],
        openfn: %{project_id: ..., endpoint: ...}  # empty map when absent
      }

  All four list keys (`:collections`, `:credentials`, `:workflows`) are
  always present; missing-from-input becomes the empty list.
  """
  @spec parse_project(binary() | map()) :: {:ok, map()} | {:error, term()}
  def parse_project(yaml_string) when is_binary(yaml_string) do
    with {:ok, parsed} <- decode(yaml_string) do
      parse_project(parsed)
    end
  end

  def parse_project(%{} = parsed) do
    parse_project_map(parsed)
  end

  def parse_project(_), do: {:error, :invalid_input}

  @doc """
  Heuristic format detection on a parsed map.

  - `steps:` present and `jobs:` absent ⇒ `:v2`
  - `jobs:` and `triggers:` and `edges:` triple ⇒ `:v1`
  - ambiguous ⇒ `:v1` with a warning logged

  See plan §Phase 2 line 230.
  """
  @spec detect_format(map() | any()) :: :v1 | :v2
  def detect_format(%{} = parsed) do
    case detect_workflow_level(parsed) do
      :v2 ->
        :v2

      :v1 ->
        :v1

      :ambiguous ->
        # Project-level docs nest workflow bodies under `workflows.<key>` —
        # peek at the children to disambiguate.
        detect_project_level(parsed)
    end
  end

  def detect_format(_), do: :v1

  # Workflow-level heuristic — look at the top-level shape only.
  defp detect_workflow_level(parsed) do
    has_steps? = has_key?(parsed, "steps") or has_key?(parsed, :steps)
    has_jobs? = has_key?(parsed, "jobs") or has_key?(parsed, :jobs)
    has_edges? = has_key?(parsed, "edges") or has_key?(parsed, :edges)

    has_v1_triggers_obj? =
      v1_triggers_object?(get(parsed, "triggers")) or
        v1_triggers_object?(get(parsed, :triggers))

    cond do
      has_steps? and not has_jobs? ->
        :v2

      has_jobs? and has_edges? and has_v1_triggers_obj? ->
        :v1

      has_jobs? and has_steps? ->
        Logger.warning(
          "YamlFormat.detect_format/1: document has both `jobs:` and `steps:`; " <>
            "treating as v1 (legacy bias)"
        )

        :v1

      true ->
        :ambiguous
    end
  end

  # Project-level heuristic — look one level deeper into `workflows.<key>`.
  # If any nested workflow body has a v2 `steps:` array we treat the whole
  # project as v2; if any has a v1 `jobs:`/`edges:` pair we treat it as v1;
  # otherwise we fall back to v1 (legacy bias) with a warning.
  defp detect_project_level(parsed) do
    workflows_block = get(parsed, "workflows") || get(parsed, :workflows)

    cond do
      is_map(workflows_block) and project_has_v2_workflow?(workflows_block) ->
        :v2

      is_map(workflows_block) and project_has_v1_workflow?(workflows_block) ->
        :v1

      true ->
        Logger.warning(
          "YamlFormat.detect_format/1: ambiguous document (no clear v1/v2 markers); " <>
            "treating as v1 (legacy bias)"
        )

        :v1
    end
  end

  defp project_has_v2_workflow?(%{} = workflows_block) do
    Enum.any?(workflows_block, fn {_k, v} ->
      is_map(v) and (has_key?(v, "steps") or has_key?(v, :steps))
    end)
  end

  defp project_has_v1_workflow?(%{} = workflows_block) do
    Enum.any?(workflows_block, fn {_k, v} ->
      is_map(v) and
        (has_key?(v, "jobs") or has_key?(v, :jobs) or
           has_key?(v, "edges") or has_key?(v, :edges))
    end)
  end

  @doc """
  Phase 3. Returns an empty map until project v2 + provisioner adapter land.
  """
  @spec to_provisioner_doc(any(), any()) :: map()
  def to_provisioner_doc(_parsed_doc, _existing_project), do: %{}

  # ── Workflow → canonical map ────────────────────────────────────────────────

  defp workflow_struct_to_canonical(%Workflow{} = workflow) do
    jobs = workflow.jobs || []
    triggers = workflow.triggers || []
    edges = workflow.edges || []

    job_id_to_key =
      jobs
      |> Enum.map(fn job -> {job.id, hyphenate(job.name)} end)
      |> Map.new()

    triggers_canonical =
      triggers
      |> Enum.sort_by(&trigger_sort_key/1)
      |> Enum.map(fn trigger ->
        trigger_to_canonical(trigger, edges, job_id_to_key, jobs)
      end)

    jobs_canonical =
      jobs
      |> Enum.sort_by(&job_sort_key/1)
      |> Enum.map(fn job ->
        job_to_canonical(job, edges, job_id_to_key)
      end)

    %{
      name: workflow.name,
      triggers: triggers_canonical,
      steps: jobs_canonical
    }
  end

  defp job_sort_key(job) do
    {job.inserted_at || ~N[1970-01-01 00:00:00], job.name}
  end

  defp trigger_sort_key(trigger) do
    {trigger.inserted_at || ~N[1970-01-01 00:00:00],
     Atom.to_string(trigger.type)}
  end

  defp trigger_to_canonical(trigger, edges, job_id_to_key, jobs) do
    base = %{
      id: Atom.to_string(trigger.type),
      type: Atom.to_string(trigger.type),
      enabled: trigger.enabled || false
    }

    base
    |> maybe_put(:openfn, trigger_openfn_blob(trigger, jobs))
    |> add_next_for_trigger(trigger, edges, job_id_to_key)
  end

  defp trigger_openfn_blob(%{type: :cron} = trigger, jobs) do
    %{}
    |> maybe_put(:cron, trigger.cron_expression)
    |> maybe_put(:cron_cursor, cron_cursor_key(trigger, jobs))
    |> nil_if_empty()
  end

  defp trigger_openfn_blob(%{type: :webhook} = trigger, _jobs) do
    case trigger.webhook_reply do
      nil -> nil
      reply -> %{webhook_reply: Atom.to_string(reply)}
    end
  end

  defp trigger_openfn_blob(%{type: :kafka} = trigger, _jobs) do
    case trigger.kafka_configuration do
      nil -> nil
      kafka -> %{kafka: kafka_config_to_canonical(kafka)}
    end
  end

  defp trigger_openfn_blob(_, _), do: nil

  defp cron_cursor_key(%{cron_cursor_job_id: nil}, _jobs), do: nil

  defp cron_cursor_key(%{cron_cursor_job_id: cursor_id}, jobs) do
    case Enum.find(jobs, fn j -> j.id == cursor_id end) do
      nil -> nil
      job -> hyphenate(job.name)
    end
  end

  defp cron_cursor_key(_, _), do: nil

  defp nil_if_empty(map) when is_map(map) do
    if map_size(map) == 0, do: nil, else: map
  end

  defp kafka_config_to_canonical(config) do
    config
    |> Map.from_struct()
    |> Map.take(@kafka_config_fields)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn
      {:hosts, hosts} when is_list(hosts) ->
        # Lightning stores hosts as [[host, port], ...]; the YAML shape is
        # ["host:port", ...] for human readability. The parser splits back.
        {:hosts,
         Enum.map(hosts, fn host_port ->
           host_port |> Enum.map(&to_string/1) |> Enum.join(":")
         end)}

      {:sasl, sasl} when is_atom(sasl) ->
        {:sasl, Atom.to_string(sasl)}

      other ->
        other
    end)
    |> Map.new()
  end

  defp job_to_canonical(job, edges, job_id_to_key) do
    base = %{
      id: hyphenate(job.name),
      name: job.name,
      adaptor: job.adaptor,
      expression: job.body
    }

    base
    |> maybe_put(:configuration, job_credential_key(job))
    |> add_next_for_step(job, edges, job_id_to_key)
  end

  defp job_credential_key(%{
         project_credential: %{credential: %{name: name}, user: %{email: email}}
       })
       when is_binary(name) and is_binary(email) do
    "#{email}|#{name}"
  end

  defp job_credential_key(%{project_credential: %Ecto.Association.NotLoaded{}}),
    do: nil

  defp job_credential_key(%{project_credential: nil}), do: nil
  defp job_credential_key(_), do: nil

  defp add_next_for_trigger(base, trigger, edges, job_id_to_key) do
    outgoing =
      edges
      |> Enum.filter(fn e -> e.source_trigger_id == trigger.id end)
      |> Enum.sort_by(fn e -> Map.get(job_id_to_key, e.target_job_id, "") end)

    add_next(base, outgoing, job_id_to_key, collapse_to_string?: true)
  end

  defp add_next_for_step(base, job, edges, job_id_to_key) do
    outgoing =
      edges
      |> Enum.filter(fn e -> e.source_job_id == job.id end)
      |> Enum.sort_by(fn e -> Map.get(job_id_to_key, e.target_job_id, "") end)

    add_next(base, outgoing, job_id_to_key, collapse_to_string?: false)
  end

  defp add_next(base, [], _job_id_to_key, _opts), do: base

  defp add_next(base, edges, job_id_to_key, opts) when is_list(edges) do
    next_map =
      edges
      |> Enum.map(fn edge ->
        target = Map.fetch!(job_id_to_key, edge.target_job_id)
        {target, edge_to_canonical(edge)}
      end)
      |> Map.new()

    next_value = maybe_collapse_next(next_map, opts)
    Map.put(base, :next, next_value)
  end

  # Collapse a single-target `:always` next map to the bare target string,
  # so triggers emit `next: target-id` instead of the verbose object form.
  # We only collapse for triggers (per the v2 spec example); job edges always
  # use the object form because their condition often differs from `:always`.
  defp maybe_collapse_next(%{} = next_map, opts) do
    if Keyword.get(opts, :collapse_to_string?, false) do
      case Map.to_list(next_map) do
        [{target, %{condition: "always"} = edge}]
        when map_size(edge) == 1 ->
          target

        _ ->
          next_map
      end
    else
      next_map
    end
  end

  defp edge_to_canonical(edge) do
    %{}
    |> Map.merge(edge_condition_pair(edge))
    |> put_unless_nil(:label, Map.get(edge, :condition_label))
    |> put_disabled(edge)
  end

  # JS expression edges emit `condition: js_expression` (literal) plus a
  # sibling `expression:` key carrying the body. Standard literal conditions
  # emit on a single line.
  defp edge_condition_pair(%{
         condition_type: :js_expression,
         condition_expression: expression
       })
       when is_binary(expression) do
    %{condition: "js_expression", expression: expression}
  end

  defp edge_condition_pair(%{condition_type: condition_type})
       when is_atom(condition_type) and not is_nil(condition_type) do
    %{condition: Atom.to_string(condition_type)}
  end

  defp edge_condition_pair(_), do: %{condition: "always"}

  # Lightning's Edge.enabled boolean inverts to v2's `disabled:` field.
  defp put_disabled(map, edge) do
    case Map.get(edge, :enabled) do
      false -> Map.put(map, :disabled, true)
      _ -> map
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  defp hyphenate(string) when is_binary(string),
    do: String.replace(string, " ", "-")

  defp hyphenate(other), do: other

  # ── Canonical map → string emitter ──────────────────────────────────────────

  @doc false
  def emit(workflow_canonical) when is_map(workflow_canonical) do
    triggers = Map.get(workflow_canonical, :triggers, [])
    jobs = Map.get(workflow_canonical, :steps, [])

    [
      emit_scalar_field("name", Map.get(workflow_canonical, :name)),
      emit_steps(triggers ++ jobs)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> ensure_trailing_newline()
  end

  defp ensure_trailing_newline(string) do
    if String.ends_with?(string, "\n"), do: string, else: string <> "\n"
  end

  defp emit_scalar_field(_key, nil), do: ""

  defp emit_scalar_field(key, value) when is_binary(value) do
    "#{key}: #{quote_if_needed(value)}"
  end

  defp emit_scalar_field(key, value)
       when is_boolean(value) or is_number(value) do
    "#{key}: #{value}"
  end

  defp emit_steps([]), do: ""

  defp emit_steps(steps) when is_list(steps) do
    body =
      steps
      |> Enum.map_join("\n", fn step -> emit_step(step, "  ") end)

    "steps:\n" <> body
  end

  defp emit_step(step, indent) do
    ordered_keys =
      cond do
        Map.has_key?(step, :type) ->
          [:id, :type, :enabled, :openfn, :next]

        true ->
          [:id, :name, :adaptor, :expression, :configuration, :next]
      end

    lines = emit_record_lines(step, ordered_keys)

    case lines do
      [first | rest] ->
        ["#{indent}- #{first}" | Enum.map(rest, fn l -> "#{indent}  #{l}" end)]
        |> Enum.join("\n")

      [] ->
        ""
    end
  end

  # Emit the body lines of a record (without the leading "- " marker).
  defp emit_record_lines(record, ordered_keys) do
    ordered_keys
    |> Enum.flat_map(fn key ->
      case Map.fetch(record, key) do
        :error -> []
        {:ok, nil} -> []
        {:ok, value} -> emit_record_field(key, value)
      end
    end)
  end

  defp emit_record_field(:expression, value) when is_binary(value) do
    multiline_block("expression", value)
  end

  defp emit_record_field(:next, target) when is_binary(target) do
    [emit_scalar_field("next", target)]
  end

  defp emit_record_field(:next, %{} = next_map) do
    if map_size(next_map) == 0 do
      []
    else
      sorted =
        next_map
        |> Enum.sort_by(fn {k, _} -> to_string(k) end)

      child_lines =
        sorted
        |> Enum.flat_map(fn {target_key, edge_obj} ->
          emit_next_target(target_key, edge_obj)
        end)

      ["next:" | child_lines]
    end
  end

  defp emit_record_field(:openfn, %{} = openfn) do
    if map_size(openfn) == 0 do
      []
    else
      ["openfn:" | emit_openfn_block(openfn)]
    end
  end

  defp emit_record_field(key, value)
       when is_atom(key) and
              (is_binary(value) or is_boolean(value) or is_number(value)) do
    [emit_scalar_field(Atom.to_string(key), value)]
  end

  defp emit_record_field(key, value) when is_atom(key) and is_list(value) do
    if value == [] do
      []
    else
      header = "#{key}:"
      items = Enum.map(value, fn v -> "  - #{quote_if_needed(to_string(v))}" end)
      [header | items]
    end
  end

  defp emit_next_target(target_key, edge_obj)
       when is_binary(target_key) or is_atom(target_key) do
    target_str = to_string(target_key)

    case edge_obj do
      %{} = obj ->
        edge_lines = emit_edge_object(obj)

        case edge_lines do
          [] ->
            ["  #{target_str}: {}"]

          lines ->
            ["  #{target_str}:" | Enum.map(lines, fn l -> "    " <> l end)]
        end
    end
  end

  defp emit_edge_object(edge) do
    [:condition, :expression, :label, :disabled]
    |> Enum.flat_map(fn key ->
      case Map.fetch(edge, key) do
        :error ->
          []

        {:ok, nil} ->
          []

        {:ok, value} when key == :condition and is_binary(value) ->
          # Standard literals (always / never / on_job_success / on_job_failure
          # / js_expression) emit on a single line. Anything else — typically a
          # bare JS expression body when `:expression` was not split out — is
          # emitted as a `|` block for readability.
          if value in @standard_condition_literals or value == "js_expression" do
            [emit_scalar_field("condition", value)]
          else
            multiline_block("condition", value)
          end

        {:ok, value} when key == :expression and is_binary(value) ->
          multiline_block("expression", value)

        {:ok, value}
        when is_binary(value) or is_boolean(value) or is_number(value) ->
          [emit_scalar_field(Atom.to_string(key), value)]
      end
    end)
  end

  defp emit_openfn_block(openfn) do
    # Stable order: cron, cron_cursor, webhook_reply, kafka, then any other
    # keys (e.g. uuid for project-level round-tripping with the CLI).
    known_order = [
      :cron,
      :cron_cursor,
      :webhook_reply,
      :kafka
    ]

    extras =
      openfn
      |> Map.keys()
      |> Enum.reject(fn k -> k in known_order end)
      |> Enum.sort_by(&to_string/1)

    (known_order ++ extras)
    |> Enum.flat_map(fn key ->
      case Map.fetch(openfn, key) do
        :error ->
          []

        {:ok, nil} ->
          []

        {:ok, %{} = nested} when key == :kafka ->
          ["  kafka:" | emit_kafka_block(nested)]

        {:ok, value} when is_list(value) ->
          if value == [] do
            []
          else
            header = "  #{key}:"

            items =
              Enum.map(value, fn v ->
                "    - #{quote_if_needed(to_string(v))}"
              end)

            [header | items]
          end

        {:ok, value}
        when is_binary(value) or is_boolean(value) or is_number(value) ->
          ["  " <> emit_scalar_field(Atom.to_string(key), value)]
      end
    end)
  end

  defp emit_kafka_block(kafka) do
    @kafka_config_fields
    |> Enum.flat_map(fn key ->
      case Map.fetch(kafka, key) do
        :error ->
          []

        {:ok, nil} ->
          []

        {:ok, list} when is_list(list) and key in [:hosts, :topics] ->
          [
            "    #{key}:"
            | Enum.map(list, fn v ->
                "      - #{quote_if_needed(to_string(v))}"
              end)
          ]

        {:ok, value}
        when is_binary(value) or is_boolean(value) or is_number(value) ->
          ["    " <> emit_scalar_field(Atom.to_string(key), value)]
      end
    end)
  end

  # Multiline literal block (`|` with two-space indent).
  defp multiline_block(key, value) do
    body_lines =
      value
      |> String.trim_trailing("\n")
      |> String.split("\n")
      |> Enum.map(fn line -> "  " <> line end)

    ["#{key}: |" | body_lines]
  end

  # Quote a scalar string when it contains characters that YAML would otherwise
  # mis-parse. The whitelist matches the v1 emitter that v2 replaced
  # (the now-deleted `Lightning.ExportUtils.yaml_safe_string/1`) so emitted
  # YAML stays compatible with downstream consumers on overlapping fields.
  defp quote_if_needed(value) when is_binary(value) do
    cond do
      value == "" ->
        "''"

      Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_\-@\.\/> |]*[a-zA-Z0-9]$/, value) and
          not yaml_reserved?(value) ->
        value

      true ->
        "'" <> String.replace(value, "'", "''") <> "'"
    end
  end

  defp quote_if_needed(value), do: to_string(value)

  defp yaml_reserved?(value) do
    String.downcase(value) in ~w(true false null yes no on off ~)
  end

  # ── Project struct → canonical map ──────────────────────────────────────────

  defp project_struct_to_canonical(%Project{} = project, snapshots) do
    project = preload_project_for_export(project)

    workflows_canonical =
      cond do
        is_list(snapshots) ->
          snapshots
          |> Enum.sort_by(& &1.name)
          |> Enum.map(&snapshot_to_canonical_workflow/1)

        true ->
          (project.workflows || [])
          |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
          |> Enum.map(&workflow_struct_to_canonical/1)
      end

    collections_canonical =
      (project.collections || [])
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&collection_to_canonical/1)

    credentials_canonical =
      (project.project_credentials || [])
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&project_credential_to_canonical/1)

    %{
      name: project.name,
      description: project.description,
      collections: collections_canonical,
      credentials: credentials_canonical,
      workflows: workflows_canonical,
      openfn: %{}
    }
  end

  # Snapshots have the same field set as a Workflow but use embedded schemas.
  # We adapt the snapshot into a `%Workflow{}` struct so the existing
  # workflow→canonical translation applies unchanged.
  defp snapshot_to_canonical_workflow(snapshot) do
    pseudo_workflow = %Workflow{
      name: snapshot.name,
      jobs: snapshot.jobs,
      triggers: snapshot.triggers,
      edges: snapshot.edges
    }

    workflow_struct_to_canonical(pseudo_workflow)
  end

  defp preload_project_for_export(%Project{} = project) do
    if assocs_loaded?(project) do
      project
    else
      Lightning.Repo.preload(project,
        project_credentials: [credential: :user],
        collections: [],
        workflows: [:jobs, :triggers, :edges]
      )
    end
  end

  defp assocs_loaded?(%Project{} = p) do
    not match?(%Ecto.Association.NotLoaded{}, p.workflows) and
      not match?(%Ecto.Association.NotLoaded{}, p.collections) and
      not match?(%Ecto.Association.NotLoaded{}, p.project_credentials)
  end

  defp collection_to_canonical(%{} = collection) do
    %{name: collection.name}
    |> maybe_put(:description, Map.get(collection, :description))
  end

  defp project_credential_to_canonical(%{credential: credential})
       when not is_nil(credential) do
    %{name: credential.name}
    |> maybe_put(:schema, Map.get(credential, :schema))
  end

  defp project_credential_to_canonical(_), do: nil

  # ── Project canonical map → string emitter ──────────────────────────────────

  @doc false
  def emit_project(project_canonical) when is_map(project_canonical) do
    [
      emit_top_scalar("name", Map.get(project_canonical, :name)),
      emit_top_description(Map.get(project_canonical, :description)),
      emit_keyed_block(
        "collections",
        Map.get(project_canonical, :collections, []),
        &emit_collection/2
      ),
      emit_keyed_block(
        "credentials",
        Map.get(project_canonical, :credentials, []),
        &emit_credential/2
      ),
      emit_keyed_block(
        "workflows",
        Map.get(project_canonical, :workflows, []),
        &emit_workflow_under_project/2
      ),
      emit_openfn_top_block(Map.get(project_canonical, :openfn))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> ensure_trailing_newline()
  end

  defp emit_top_scalar(_key, nil), do: ""

  defp emit_top_scalar(key, value) when is_binary(value) do
    "#{key}: #{quote_if_needed(value)}"
  end

  defp emit_top_scalar(key, value) when is_boolean(value) or is_number(value) do
    "#{key}: #{value}"
  end

  defp emit_top_description(nil), do: ""
  defp emit_top_description(""), do: ""

  defp emit_top_description(value) when is_binary(value) do
    multiline_block("description", value) |> Enum.join("\n")
  end

  # Emit a keyed block of records:
  #
  #     collections:
  #       <name>:
  #         <body>
  #
  # `record_emit_fn` receives `(record, indent)` and returns the body lines as
  # a list of pre-indented strings.
  defp emit_keyed_block(_key, [], _record_emit_fn), do: ""
  defp emit_keyed_block(_key, nil, _record_emit_fn), do: ""

  defp emit_keyed_block(key, records, record_emit_fn) when is_list(records) do
    body =
      records
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn record ->
        record_key = hyphenate(record.name)
        body_lines = record_emit_fn.(record, "    ")

        case body_lines do
          [] -> "  #{record_key}: {}"
          _ -> "  #{record_key}:\n" <> Enum.join(body_lines, "\n")
        end
      end)

    case body do
      [] -> ""
      _ -> "#{key}:\n" <> Enum.join(body, "\n")
    end
  end

  defp emit_collection(record, indent) do
    [
      {:description, Map.get(record, :description)}
    ]
    |> Enum.flat_map(fn
      {_k, nil} ->
        []

      {:description, value} when is_binary(value) ->
        # description on collections is short; emit single-line if no newlines
        if String.contains?(value, "\n") do
          multiline_block("description", value)
          |> Enum.map(fn l -> indent <> l end)
        else
          [indent <> emit_scalar_field("description", value)]
        end
    end)
  end

  defp emit_credential(record, indent) do
    [
      {:schema, Map.get(record, :schema)}
    ]
    |> Enum.flat_map(fn
      {_k, nil} -> []
      {k, v} -> [indent <> emit_scalar_field(Atom.to_string(k), v)]
    end)
  end

  defp emit_workflow_under_project(workflow_canonical, indent) do
    name = Map.get(workflow_canonical, :name)
    triggers = Map.get(workflow_canonical, :triggers, [])
    jobs = Map.get(workflow_canonical, :steps, [])
    steps = triggers ++ jobs

    name_line =
      case name do
        nil -> []
        n -> [indent <> emit_scalar_field("name", n)]
      end

    steps_lines =
      case steps do
        [] ->
          []

        list ->
          step_indent = indent <> "  "

          [
            indent <> "steps:"
            | Enum.map(list, fn step -> emit_step(step, step_indent) end)
          ]
      end

    name_line ++ steps_lines
  end

  defp emit_openfn_top_block(nil), do: ""
  defp emit_openfn_top_block(map) when map_size(map) == 0, do: ""

  defp emit_openfn_top_block(%{} = openfn) do
    lines =
      openfn
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.flat_map(fn
        {_k, nil} ->
          []

        {k, v} when is_binary(v) or is_boolean(v) or is_number(v) ->
          ["  " <> emit_scalar_field(to_string(k), v)]
      end)

    case lines do
      [] -> ""
      _ -> "openfn:\n" <> Enum.join(lines, "\n")
    end
  end

  # ── Parser (string → canonical map) ─────────────────────────────────────────
  #
  # Lightning has no YAML dependency. Rather than add one for v2's small,
  # well-controlled subset, we parse the slice we emit ourselves. The parser
  # accepts what `emit/1` produces plus the v1 fixture shape (block-style
  # mappings, `|` literal scalars, simple flow values).

  defp decode(yaml_string) when is_binary(yaml_string) do
    lines =
      yaml_string
      |> String.split(~r/\r?\n/)
      |> Enum.with_index()
      |> Enum.reject(fn {line, _idx} ->
        trimmed = String.trim_leading(line)
        trimmed == "" or String.starts_with?(trimmed, "#")
      end)

    case parse_block(lines, 0) do
      {value, []} -> {:ok, value}
      {value, _rest} -> {:ok, value}
    end
  rescue
    err -> {:error, {:yaml_decode_failed, err}}
  end

  # Parse a block at `indent` columns; returns {value, remaining_lines}.
  defp parse_block([], _indent), do: {nil, []}

  defp parse_block([{line, _idx} | rest] = lines, indent) do
    cur_indent = leading_spaces(line)
    trimmed = String.trim_leading(line)

    cond do
      cur_indent < indent ->
        {nil, lines}

      String.starts_with?(trimmed, "- ") or trimmed == "-" ->
        parse_sequence(lines, cur_indent)

      String.contains?(trimmed, ":") ->
        parse_mapping(lines, cur_indent)

      true ->
        {scalar_decode(trimmed), rest}
    end
  end

  defp parse_mapping(lines, indent) do
    parse_mapping_loop(lines, indent, %{}, [])
  end

  defp parse_mapping_loop([], _indent, acc, key_order) do
    {%{__map: acc, __order: Enum.reverse(key_order)} |> finalize_map(), []}
  end

  defp parse_mapping_loop([{line, _idx} | rest] = all, indent, acc, key_order) do
    cur_indent = leading_spaces(line)

    cond do
      cur_indent < indent ->
        {%{__map: acc, __order: Enum.reverse(key_order)} |> finalize_map(), all}

      cur_indent > indent ->
        # Continuation of a previous key — shouldn't reach here normally
        {%{__map: acc, __order: Enum.reverse(key_order)} |> finalize_map(), all}

      true ->
        {key, after_key} = split_key(line)
        value_part = after_key

        cond do
          value_part == "" or value_part == nil ->
            # Nested block follows
            {value, rest2} = parse_nested(rest, indent)

            parse_mapping_loop(rest2, indent, Map.put(acc, key, value), [
              key | key_order
            ])

          value_part == "|" ->
            {literal, rest2} = consume_literal_block(rest, indent)

            parse_mapping_loop(rest2, indent, Map.put(acc, key, literal), [
              key | key_order
            ])

          true ->
            value = scalar_decode(value_part)

            parse_mapping_loop(rest, indent, Map.put(acc, key, value), [
              key | key_order
            ])
        end
    end
  end

  defp finalize_map(%{__map: m}), do: m

  defp parse_nested([], _parent_indent), do: {nil, []}

  defp parse_nested([{line, _idx} | _] = lines, parent_indent) do
    cur_indent = leading_spaces(line)
    trimmed = String.trim_leading(line)

    cond do
      cur_indent <= parent_indent ->
        {nil, lines}

      String.starts_with?(trimmed, "- ") or trimmed == "-" ->
        parse_sequence(lines, cur_indent)

      true ->
        parse_mapping(lines, cur_indent)
    end
  end

  defp parse_sequence(lines, indent) do
    parse_sequence_loop(lines, indent, [])
  end

  defp parse_sequence_loop([], _indent, acc), do: {Enum.reverse(acc), []}

  defp parse_sequence_loop([{line, _idx} | rest] = all, indent, acc) do
    cur_indent = leading_spaces(line)

    cond do
      cur_indent < indent ->
        {Enum.reverse(acc), all}

      cur_indent > indent ->
        {Enum.reverse(acc), all}

      true ->
        trimmed = String.trim_leading(line)

        if not (String.starts_with?(trimmed, "- ") or trimmed == "-") do
          {Enum.reverse(acc), all}
        else
          inline = String.trim_leading(trimmed, "-") |> String.trim_leading(" ")

          cond do
            inline == "" ->
              {value, rest2} = parse_nested(rest, indent)
              parse_sequence_loop(rest2, indent, [value | acc])

            inline_mapping_first_line?(inline) ->
              # First item of an inline mapping; the rest of its keys live in
              # subsequent lines indented two beyond the marker.
              child_indent = indent + 2
              {key, after_key} = split_key_from_inline(inline)

              first_pair =
                cond do
                  after_key == "" ->
                    {key, fetch_nested_after_inline(rest, child_indent)}

                  after_key == "|" ->
                    {literal, _} = consume_literal_block(rest, child_indent)
                    {key, literal}

                  true ->
                    {key, scalar_decode(after_key)}
                end

              {item_map, rest2} =
                continue_inline_mapping(rest, child_indent, first_pair)

              parse_sequence_loop(rest2, indent, [item_map | acc])

            true ->
              # Plain scalar list item
              parse_sequence_loop(rest, indent, [scalar_decode(inline) | acc])
          end
        end
    end
  end

  defp continue_inline_mapping(lines, child_indent, {first_key, first_value}) do
    {{rest_map, post_rest}, _} =
      case first_value do
        v ->
          {parse_mapping_continuation(lines, child_indent, %{first_key => v}, [
             first_key
           ]), :ok}
      end

    {rest_map, post_rest}
  end

  defp parse_mapping_continuation(lines, indent, acc, _key_order) do
    {map, rest} = parse_mapping_at_indent(lines, indent)

    case map do
      %{} -> {Map.merge(map, acc) |> Map.merge(map), rest}
      _ -> {acc, rest}
    end
    |> reorder_with_acc(acc)
  end

  defp reorder_with_acc({merged, rest}, _acc) do
    {merged, rest}
  end

  defp parse_mapping_at_indent([], _indent), do: {%{}, []}

  defp parse_mapping_at_indent([{line, _idx} | _] = all, indent) do
    cur_indent = leading_spaces(line)

    cond do
      cur_indent < indent -> {%{}, all}
      cur_indent > indent -> {%{}, all}
      true -> parse_mapping(all, indent)
    end
  end

  # When a sequence item begins with a key like `- id: foo`, subsequent keys of
  # that same item live indented at child_indent. Returns the parsed value
  # following an inline `key:` whose value spans the next block.
  defp fetch_nested_after_inline(lines, child_indent) do
    {value, _rest} = parse_nested(lines, child_indent - 2)
    value
  end

  # A line whose first unquoted segment ends with `: ` or `:` at EOL
  # represents the first key of a mapping. Quoted scalars containing `:` (like
  # `'localhost:9092'`) must NOT be treated as mappings.
  defp inline_mapping_first_line?(line) when is_binary(line) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, "'") -> false
      String.starts_with?(trimmed, "\"") -> false
      true -> Regex.match?(~r/^[^:'"\s][^:'"]*:(\s|$)/, trimmed)
    end
  end

  defp split_key(line) do
    trimmed = String.trim_leading(line)
    [k, rest] = split_once(trimmed, ":")
    {k, String.trim_leading(rest)}
  end

  defp split_key_from_inline(inline) do
    [k, rest] = split_once(inline, ":")
    {k, String.trim_leading(rest)}
  end

  defp split_once(string, sep) do
    case String.split(string, sep, parts: 2) do
      [a] -> [a, ""]
      [a, b] -> [a, b]
    end
  end

  defp consume_literal_block(lines, key_indent) do
    consume_literal_loop(lines, key_indent, [])
  end

  defp consume_literal_loop([], _key_indent, acc) do
    {acc |> Enum.reverse() |> Enum.join("\n") |> append_newline(), []}
  end

  defp consume_literal_loop([{line, _idx} = head | rest] = all, key_indent, acc) do
    cur_indent = leading_spaces(line)
    trimmed_full = String.trim_leading(line)

    cond do
      trimmed_full == "" ->
        consume_literal_loop(rest, key_indent, ["" | acc])

      cur_indent > key_indent ->
        # Strip the block's indent prefix (key_indent + 2)
        prefix_len = key_indent + 2

        stripped =
          if String.length(line) >= prefix_len do
            String.slice(line, prefix_len, String.length(line))
          else
            String.trim_leading(line)
          end

        consume_literal_loop(rest, key_indent, [stripped | acc])

      true ->
        # Dedented — block ends here
        _ = head
        {acc |> Enum.reverse() |> Enum.join("\n") |> append_newline(), all}
    end
  end

  defp append_newline(""), do: ""
  defp append_newline(s), do: s <> "\n"

  defp scalar_decode(""), do: nil
  defp scalar_decode("null"), do: nil
  defp scalar_decode("~"), do: nil
  defp scalar_decode("true"), do: true
  defp scalar_decode("false"), do: false

  defp scalar_decode(s) when is_binary(s) do
    cond do
      String.starts_with?(s, "'") and String.ends_with?(s, "'") ->
        s |> String.slice(1..-2//1) |> String.replace("''", "'")

      String.starts_with?(s, "\"") and String.ends_with?(s, "\"") ->
        s |> String.slice(1..-2//1)

      Regex.match?(~r/^-?\d+$/, s) ->
        String.to_integer(s)

      Regex.match?(~r/^-?\d+\.\d+$/, s) ->
        String.to_float(s)

      true ->
        s
    end
  end

  defp leading_spaces(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " "))
    |> length()
  end

  # ── Parsed-map → canonical workflow map ─────────────────────────────────────

  defp parse_workflow_map(parsed) do
    name = get(parsed, "name") || get(parsed, :name)
    steps_raw = get(parsed, "steps") || get(parsed, :steps) || []

    cond do
      not is_list(steps_raw) ->
        {:error, :steps_must_be_array}

      true ->
        records = Enum.map(steps_raw, &parse_step/1)

        {triggers, jobs} =
          Enum.split_with(records, fn r -> Map.has_key?(r, :type) end)

        with :ok <- validate_next_references(triggers ++ jobs) do
          {:ok, %{name: name, triggers: triggers, steps: jobs}}
        end
    end
  end

  # ── Parsed-map → canonical project map ──────────────────────────────────────

  defp parse_project_map(parsed) do
    name = dual_get(parsed, :name)
    description = dual_get(parsed, :description)

    collections =
      parse_keyed_block(dual_get(parsed, :collections), &parse_collection/2)

    credentials =
      parse_keyed_block(dual_get(parsed, :credentials), &parse_credential/2)

    workflows_raw = dual_get(parsed, :workflows)

    with {:ok, workflows} <- parse_workflows_block(workflows_raw) do
      openfn = parse_project_openfn(dual_get(parsed, :openfn))

      {:ok,
       %{
         name: name,
         description: description,
         collections: collections,
         credentials: credentials,
         workflows: workflows,
         openfn: openfn
       }}
    end
  end

  defp parse_keyed_block(nil, _record_parse_fn), do: []

  defp parse_keyed_block(%{} = raw, record_parse_fn) do
    raw
    |> Enum.map(fn {key, value} ->
      record_parse_fn.(to_string(key), value)
    end)
  end

  defp parse_keyed_block(_, _record_parse_fn), do: []

  defp parse_collection(name, %{} = raw) do
    %{name: name}
    |> maybe_put(:description, dual_get(raw, :description))
  end

  defp parse_collection(name, _raw), do: %{name: name}

  defp parse_credential(name, %{} = raw) do
    %{name: name}
    |> maybe_put(:schema, dual_get(raw, :schema))
  end

  defp parse_credential(name, _raw), do: %{name: name}

  defp parse_workflows_block(nil), do: {:ok, []}

  defp parse_workflows_block(%{} = raw) do
    workflows =
      Enum.map(raw, fn {key, value} ->
        case parse_workflow_map(value || %{}) do
          {:ok, wf} ->
            # Use the explicit `name:` field when present; otherwise fall back
            # to the hyphenated map key.
            Map.put(wf, :name, wf[:name] || to_string(key))

          {:error, _reason} = err ->
            err
        end
      end)

    case Enum.find(workflows, &match?({:error, _}, &1)) do
      nil -> {:ok, workflows}
      err -> err
    end
  end

  defp parse_workflows_block(_), do: {:ok, []}

  defp parse_project_openfn(nil), do: %{}

  defp parse_project_openfn(%{} = raw) do
    raw
    |> Enum.into(%{}, fn {k, v} -> {to_string_atom_key(k), v} end)
  end

  defp parse_project_openfn(_), do: %{}

  # A step with a `type:` key is a trigger; everything else is a job.
  defp parse_step(raw) when is_map(raw) do
    case dual_get(raw, :type) do
      nil -> parse_job_step(raw)
      _type -> parse_trigger_step(raw)
    end
  end

  defp parse_trigger_step(raw) do
    %{
      id: dual_get(raw, :id),
      type: dual_get(raw, :type),
      enabled: dual_get(raw, :enabled, false)
    }
    |> maybe_put(:openfn, parse_openfn(dual_get(raw, :openfn)))
    |> maybe_put(:next, parse_next(dual_get(raw, :next)))
  end

  defp parse_job_step(raw) do
    %{
      id: dual_get(raw, :id),
      name: dual_get(raw, :name),
      adaptor: dual_get(raw, :adaptor),
      expression: dual_get(raw, :expression)
    }
    |> maybe_put(:configuration, dual_get(raw, :configuration))
    |> maybe_put(:next, parse_next(dual_get(raw, :next)))
  end

  defp parse_openfn(nil), do: nil

  defp parse_openfn(%{} = raw) do
    base = %{}

    base =
      Enum.reduce([:cron, :cron_cursor, :webhook_reply], base, fn k, acc ->
        case dual_get(raw, k) do
          nil -> acc
          v -> Map.put(acc, k, v)
        end
      end)

    base =
      case dual_get(raw, :kafka) do
        nil -> base
        v -> Map.put(base, :kafka, parse_kafka(v))
      end

    # Anything else (e.g. uuid for round-tripping with the CLI) is preserved.
    extras =
      raw
      |> Enum.reject(fn {k, _} ->
        to_string(k) in ["cron", "cron_cursor", "webhook_reply", "kafka"]
      end)
      |> Enum.into(%{}, fn {k, v} -> {to_string_atom_key(k), v} end)

    merged = Map.merge(extras, base)

    if map_size(merged) == 0, do: nil, else: merged
  end

  defp to_string_atom_key(k) when is_atom(k), do: k

  defp to_string_atom_key(k) when is_binary(k) do
    try do
      String.to_existing_atom(k)
    rescue
      _ -> k
    end
  end

  defp parse_kafka(nil), do: nil

  defp parse_kafka(%{} = raw) do
    @kafka_config_fields
    |> Enum.reduce(%{}, fn key, acc ->
      case dual_get(raw, key) do
        nil -> acc
        v -> Map.put(acc, key, v)
      end
    end)
  end

  defp parse_next(nil), do: nil

  defp parse_next(value) when is_binary(value), do: value

  defp parse_next(%{} = raw) do
    raw
    |> Enum.into(%{}, fn {target, edge} ->
      target_key = to_string(target)
      {target_key, parse_edge(edge)}
    end)
  end

  defp parse_edge(%{} = raw) do
    %{}
    |> maybe_put(:condition, dual_get(raw, :condition, "always"))
    |> maybe_put(:expression, dual_get(raw, :expression))
    |> maybe_put(:label, dual_get(raw, :label))
    |> maybe_put(:disabled, dual_get(raw, :disabled))
  end

  defp validate_next_references(records) do
    valid_targets =
      records
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    next_targets =
      Enum.flat_map(records, fn record ->
        case Map.get(record, :next) do
          nil -> []
          target when is_binary(target) -> [target]
          %{} = m -> Map.keys(m)
        end
      end)
      |> Enum.uniq()

    case Enum.reject(next_targets, &MapSet.member?(valid_targets, &1)) do
      [] -> :ok
      missing -> {:error, {:dangling_next_references, missing}}
    end
  end

  # ── small helpers ───────────────────────────────────────────────────────────

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get(map, key) when is_map(map), do: Map.get(map, key)
  defp get(_, _), do: nil

  # Look up a key in a parsed YAML map, accepting either string or atom forms.
  # Distinct from `||` chains because we treat `false` as a present value.
  defp dual_get(map, key, default \\ nil) when is_atom(key) do
    cond do
      Map.has_key?(map, Atom.to_string(key)) ->
        Map.fetch!(map, Atom.to_string(key))

      Map.has_key?(map, key) ->
        Map.fetch!(map, key)

      true ->
        default
    end
  end

  defp has_key?(map, key) when is_map(map), do: Map.has_key?(map, key)
  defp has_key?(_, _), do: false

  defp v1_triggers_object?(%{} = m) when not is_struct(m) do
    # v1 triggers is a keyed object whose values are maps with a `type:` key
    Enum.any?(m, fn
      {_k, %{} = v} -> Map.has_key?(v, "type") or Map.has_key?(v, :type)
      _ -> false
    end)
  end

  defp v1_triggers_object?(_), do: false
end
