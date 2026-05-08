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

  Before emission, the canonical map splits the single `steps:` array into
  two sibling keys — `:triggers` and `:steps` — so the emitter can iterate
  triggers and jobs separately. Both keys are always present (empty list
  when there are none).

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
  """

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Workflow

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
      id: hyphenate(workflow.name),
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
    type_str = Atom.to_string(trigger.type)

    base = %{
      id: type_str,
      name: type_str,
      enabled: trigger.enabled || false,
      # `type:` and the `openfn:` blob are Lightning extensions to the
      # portability spec, which leaves trigger fields explicitly TODO.
      type: type_str
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
      expression: job.body
    }

    base
    |> maybe_put(:adaptors, adaptors_list(job.adaptor))
    |> maybe_put(:configuration, job_credential_key(job))
    |> add_next_for_step(job, edges, job_id_to_key)
  end

  defp adaptors_list(nil), do: nil
  defp adaptors_list(""), do: nil
  defp adaptors_list(adaptor) when is_binary(adaptor), do: [adaptor]

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

    add_next(base, outgoing, job_id_to_key, collapse_to_string?: true)
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

  # Collapse a single-target unconditional next map to the bare target string,
  # so triggers and unconditional job edges emit `next: target-id` instead of
  # the verbose object form. An "unconditional" edge is `:always` with no
  # label or disabled flag, which canonicalises to an empty edge map.
  defp maybe_collapse_next(%{} = next_map, opts) do
    if Keyword.get(opts, :collapse_to_string?, false) do
      case Map.to_list(next_map) do
        [{target, edge}] when map_size(edge) == 0 -> target
        _ -> next_map
      end
    else
      next_map
    end
  end

  defp edge_to_canonical(edge) do
    %{}
    |> maybe_put(:condition, edge_condition_js(edge))
    |> put_unless_nil(:label, Map.get(edge, :condition_label))
    |> put_disabled(edge)
  end

  # Map Lightning's internal condition_type to a JS expression body, per the
  # portability spec (`condition` is "Javascript expression (function body,
  # not function)"). `:always` becomes nil — caller omits the key entirely.
  # The canonical strings here are matched verbatim on the parse side to
  # round-trip back to the original condition_type.
  defp edge_condition_js(%{
         condition_type: :js_expression,
         condition_expression: expression
       })
       when is_binary(expression) do
    expression
  end

  defp edge_condition_js(%{condition_type: :on_job_success}), do: "!state.errors"

  defp edge_condition_js(%{condition_type: :on_job_failure}),
    do: "!!state.errors"

  defp edge_condition_js(%{condition_type: :always}), do: nil
  defp edge_condition_js(_), do: nil

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
          [:id, :name, :enabled, :type, :openfn, :next]

        true ->
          [:id, :name, :adaptors, :expression, :configuration, :next]
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
    [:condition, :label, :disabled]
    |> Enum.flat_map(fn key ->
      case Map.fetch(edge, key) do
        :error ->
          []

        {:ok, nil} ->
          []

        {:ok, value} when key == :condition and is_binary(value) ->
          # Per the portability spec, `condition` is a JS expression body.
          # Multi-line bodies emit as a `|` literal block; single-line bodies
          # emit as a quoted scalar.
          if String.contains?(value, "\n") do
            multiline_block("condition", value)
          else
            [emit_scalar_field("condition", value)]
          end

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

    # Collections are emitted as a string list of names (spec: `string[]`),
    # alphabetically sorted for stable output.
    collections_canonical =
      (project.collections || [])
      |> Enum.map(& &1.name)
      |> Enum.sort()

    # Credentials are emitted as `[{name, owner}]`. The spec requires both
    # fields, so we drop entries with no resolvable owner email.
    credentials_canonical =
      (project.project_credentials || [])
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.flat_map(&project_credential_to_canonical/1)

    %{
      id: hyphenate(project.name),
      name: project.name,
      description: project.description,
      collections: collections_canonical,
      credentials: credentials_canonical,
      workflows: workflows_canonical
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

  # Returns a single-element list (so callers can flat_map and skip silent
  # drops) or empty list when the credential has no owner email.
  defp project_credential_to_canonical(%{credential: %{name: name} = credential})
       when is_binary(name) do
    case credential do
      %{user: %{email: email}} when is_binary(email) ->
        [%{name: name, owner: email}]

      _ ->
        []
    end
  end

  defp project_credential_to_canonical(_), do: []

  # ── Project canonical map → string emitter ──────────────────────────────────

  @doc false
  def emit_project(project_canonical) when is_map(project_canonical) do
    [
      emit_top_scalar("id", Map.get(project_canonical, :id)),
      emit_top_scalar("name", Map.get(project_canonical, :name)),
      emit_top_description(Map.get(project_canonical, :description)),
      emit_collections_array(Map.get(project_canonical, :collections, [])),
      emit_credentials_array(Map.get(project_canonical, :credentials, [])),
      emit_workflows_array(Map.get(project_canonical, :workflows, []))
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

  # Spec: `collections?: string[]`. Emit as a YAML sequence of names.
  defp emit_collections_array([]), do: ""
  defp emit_collections_array(nil), do: ""

  defp emit_collections_array(names) when is_list(names) do
    items =
      names
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn name -> "  - #{quote_if_needed(to_string(name))}" end)

    case items do
      [] -> ""
      _ -> "collections:\n" <> Enum.join(items, "\n")
    end
  end

  # Spec: `credentials?: Credential[]` where `Credential = {name, owner}`.
  defp emit_credentials_array([]), do: ""
  defp emit_credentials_array(nil), do: ""

  defp emit_credentials_array(records) when is_list(records) do
    items =
      records
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn record ->
        "  - name: #{quote_if_needed(to_string(record.name))}\n" <>
          "    owner: #{quote_if_needed(to_string(record.owner))}"
      end)

    case items do
      [] -> ""
      _ -> "credentials:\n" <> Enum.join(items, "\n")
    end
  end

  # Spec: `workflows: WorkflowSpec[]`. Emit as a YAML sequence of objects.
  defp emit_workflows_array([]), do: ""
  defp emit_workflows_array(nil), do: ""

  defp emit_workflows_array(workflows) when is_list(workflows) do
    items = Enum.map(workflows, &emit_workflow_array_item/1)

    case items do
      [] -> ""
      _ -> "workflows:\n" <> Enum.join(items, "\n")
    end
  end

  defp emit_workflow_array_item(workflow_canonical) do
    triggers = Map.get(workflow_canonical, :triggers, [])
    jobs = Map.get(workflow_canonical, :steps, [])
    steps = triggers ++ jobs

    head_lines =
      [:id, :name]
      |> Enum.flat_map(fn key ->
        case Map.get(workflow_canonical, key) do
          nil -> []
          val -> [emit_scalar_field(Atom.to_string(key), val)]
        end
      end)

    [first | rest] = head_lines

    steps_lines =
      case steps do
        [] ->
          []

        list ->
          [
            "    steps:"
            | Enum.map(list, fn step -> emit_step(step, "      ") end)
          ]
      end

    body =
      ["  - #{first}"] ++
        Enum.map(rest, fn l -> "    #{l}" end) ++
        steps_lines

    Enum.join(body, "\n")
  end

  # ── small helpers ───────────────────────────────────────────────────────────

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
