defmodule Lightning.Workflows.YamlFormat do
  @moduledoc """
  Single boundary between Lightning's runtime structs and YAML files.
  Knows about format versions; delegates to `V1` (parse-only) or `V2`.

  Outbound (export) writes V2 only — v1 export was deleted in Phase 4.
  Inbound (parse) auto-detects V1 vs V2.
  """

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.YamlFormat.V1
  alias Lightning.Workflows.YamlFormat.V2

  @type format_version :: :v1 | :v2
  @type parsed_doc :: %{format: format_version(), doc: map()}

  # ── Outbound ──────────────────────────────────────────────────────────────

  @spec serialize_workflow(Workflow.t()) :: {:ok, binary()} | {:error, term()}
  def serialize_workflow(workflow) do
    V2.serialize_workflow(workflow)
  end

  @spec serialize_project(Project.t(), [Snapshot.t()] | nil) ::
          {:ok, binary()} | {:error, term()}
  def serialize_project(project, snapshots \\ nil) do
    V2.serialize_project(project, snapshots)
  end

  # ── Inbound ───────────────────────────────────────────────────────────────

  @spec parse_workflow(binary() | map()) ::
          {:ok, parsed_doc()} | {:error, term()}
  def parse_workflow(yaml_string) when is_binary(yaml_string) do
    yaml_string
    |> detect_format()
    |> dispatch_parse_workflow(yaml_string)
  end

  def parse_workflow(%{} = parsed) do
    parsed
    |> detect_format()
    |> dispatch_parse_workflow(parsed)
  end

  def parse_workflow(_other), do: {:error, :invalid_input}

  @spec parse_project(binary() | map()) ::
          {:ok, parsed_doc()} | {:error, term()}
  def parse_project(yaml_string) when is_binary(yaml_string) do
    yaml_string
    |> detect_format()
    |> dispatch_parse_project(yaml_string)
  end

  def parse_project(%{} = parsed) do
    parsed
    |> detect_format()
    |> dispatch_parse_project(parsed)
  end

  def parse_project(_other), do: {:error, :invalid_input}

  @doc """
  Detect the format of a parsed YAML map (or raw string).

  Delegates to `V2.detect_format/1`, which encodes the heuristic spelled out
  in the plan: `steps:` present + `jobs:` absent ⇒ `:v2`; the v1 triple ⇒
  `:v1`; anything else ⇒ `:v1` with a warning.

  Strings are not parsed here — callers should parse first and hand the map
  in (parsing twice is wasteful and the V2 module's parser would reject v1
  shape outright). When given a string we make a best-effort cheap regex check
  so the dispatch helpers don't have to special-case input type.
  """
  @spec detect_format(map() | binary()) :: format_version()
  def detect_format(parsed) when is_map(parsed) do
    V2.detect_format(parsed)
  end

  def detect_format(yaml_string) when is_binary(yaml_string) do
    # Match `steps:` at any indent level (project files nest workflow bodies
    # under `workflows: <key>:` so the `steps:` line is indented). The lack
    # of any `jobs:` mapping anywhere disambiguates from v1.
    has_steps? = Regex.match?(~r/^\s*steps\s*:/m, yaml_string)
    has_jobs? = Regex.match?(~r/^\s*jobs\s*:/m, yaml_string)

    if has_steps? and not has_jobs?, do: :v2, else: :v1
  end

  def detect_format(_other), do: :v1

  defp dispatch_parse_workflow(:v1, yaml_string) when is_binary(yaml_string) do
    yaml_string |> V1.parse_workflow() |> wrap_parsed(:v1)
  end

  # An already-parsed map in v1 territory is the legacy provisioner-shape
  # JSON the API has accepted since day one. There is no server-side v1 YAML
  # parser, so we treat the map as canonical and let `to_provisioner_doc/2`
  # passthrough it.
  defp dispatch_parse_workflow(:v1, %{} = parsed) do
    {:ok, %{format: :v1, doc: parsed}}
  end

  defp dispatch_parse_workflow(:v2, yaml_string) when is_binary(yaml_string) do
    yaml_string |> V2.parse_workflow() |> wrap_parsed(:v2)
  end

  defp dispatch_parse_workflow(:v2, %{} = parsed) do
    parsed |> V2.parse_workflow() |> wrap_parsed(:v2)
  end

  defp dispatch_parse_project(:v1, yaml_string) when is_binary(yaml_string) do
    yaml_string |> V1.parse_project() |> wrap_parsed(:v1)
  end

  defp dispatch_parse_project(:v1, %{} = parsed) do
    {:ok, %{format: :v1, doc: parsed}}
  end

  defp dispatch_parse_project(:v2, yaml_string) when is_binary(yaml_string) do
    yaml_string |> V2.parse_project() |> wrap_parsed(:v2)
  end

  defp dispatch_parse_project(:v2, %{} = parsed) do
    parsed |> V2.parse_project() |> wrap_parsed(:v2)
  end

  @spec wrap_parsed({:ok, map()} | {:error, term()}, format_version()) ::
          {:ok, parsed_doc()} | {:error, term()}
  defp wrap_parsed({:ok, doc}, format), do: {:ok, %{format: format, doc: doc}}
  defp wrap_parsed({:error, _} = err, _format), do: err

  # ── Provisioner bridge ────────────────────────────────────────────────────

  @spec to_provisioner_doc(parsed_doc(), Project.t() | nil) :: map()
  def to_provisioner_doc(%{format: :v1, doc: doc}, _existing_project) do
    # The existing v1 path already produces provisioner-shaped maps.
    doc
  end

  def to_provisioner_doc(%{format: :v2, doc: doc}, existing_project) do
    index = build_existing_index(existing_project)
    v2_canonical_to_provisioner(doc, index)
  end

  # ── v2 → provisioner translation ────────────────────────────────────────

  # Walks the canonical project map and produces a provisioner-shaped map
  # with UUIDs injected at every record level (project / workflow / job /
  # trigger / edge / collection / credential). Stable hyphenated names are
  # the join key; if the existing project has a record with that name, we
  # reuse its UUID; otherwise we mint a fresh one.
  defp v2_canonical_to_provisioner(canonical, index) do
    workflows =
      canonical
      |> Map.get(:workflows, [])
      |> Enum.map(fn wf -> v2_workflow_to_provisioner(wf, index) end)

    collections =
      canonical
      |> Map.get(:collections, [])
      |> Enum.map(fn c ->
        %{
          "id" => lookup_or_mint(index, [:collections, c.name]),
          "name" => c.name
        }
      end)

    %{
      "id" => index.project_id || Ecto.UUID.generate(),
      "name" => Map.get(canonical, :name),
      "description" => Map.get(canonical, :description),
      "workflows" => workflows,
      "collections" => collections
    }
    |> drop_nil_keys()
    |> maybe_put_credentials(canonical, index)
  end

  defp maybe_put_credentials(map, canonical, index) do
    credentials = Map.get(canonical, :credentials, [])

    project_credentials =
      credentials
      |> Enum.flat_map(fn cred ->
        # When there's an existing project, match the credential by name and
        # reuse the project_credential.id. When there isn't, we can't safely
        # bind to a real credential record (v2 YAML carries no owner) so we
        # omit the entry — callers can attach credentials in a follow-up flow.
        case Map.get(index.credentials, cred.name) do
          nil ->
            []

          %{id: id, owner_email: email} when is_binary(email) ->
            [%{"id" => id, "name" => cred.name, "owner" => email}]

          %{id: id} ->
            [%{"id" => id, "name" => cred.name}]
        end
      end)

    case project_credentials do
      [] -> map
      list -> Map.put(map, "project_credentials", list)
    end
  end

  defp v2_workflow_to_provisioner(wf, index) do
    name = Map.get(wf, :name)
    workflow_index = Map.get(index.workflows, name, %{})

    # Build a per-workflow lookup of job-name → existing UUID
    job_index = Map.get(workflow_index, :jobs, %{})
    trigger_index = Map.get(workflow_index, :triggers, %{})
    edge_index = Map.get(workflow_index, :edges, %{})

    triggers = Map.get(wf, :triggers, [])
    steps = Map.get(wf, :steps, [])

    # Map step.id (hyphenated name) → assigned UUID for this workflow's jobs.
    job_id_map =
      steps
      |> Map.new(fn step ->
        step_id = step.id
        uuid = Map.get(job_index, step_id) || Ecto.UUID.generate()
        {step_id, uuid}
      end)

    # Map trigger.id (the `type` string) → assigned UUID.
    trigger_id_map =
      triggers
      |> Map.new(fn trigger ->
        trigger_id = trigger.id
        uuid = Map.get(trigger_index, trigger_id) || Ecto.UUID.generate()
        {trigger_id, uuid}
      end)

    jobs_payload =
      Enum.map(steps, fn s -> v2_job_to_provisioner(s, job_id_map) end)

    triggers_payload =
      Enum.map(triggers, fn t ->
        v2_trigger_to_provisioner(t, job_id_map, trigger_id_map)
      end)

    edges_payload =
      build_edges_from_v2(
        triggers,
        steps,
        job_id_map,
        trigger_id_map,
        edge_index
      )

    %{
      "id" => Map.get(workflow_index, :id) || Ecto.UUID.generate(),
      "name" => name,
      "jobs" => jobs_payload,
      "triggers" => triggers_payload,
      "edges" => edges_payload
    }
  end

  defp v2_job_to_provisioner(step, job_id_map) do
    %{
      "id" => Map.fetch!(job_id_map, step.id),
      "name" => Map.get(step, :name) || step.id,
      "adaptor" => Map.get(step, :adaptor),
      "body" => Map.get(step, :expression)
    }
    |> drop_nil_keys()
  end

  defp v2_trigger_to_provisioner(trigger, job_id_map, trigger_id_map) do
    type = Map.get(trigger, :type)
    openfn = Map.get(trigger, :openfn) || %{}

    base = %{
      "id" => Map.fetch!(trigger_id_map, trigger.id),
      "type" => type,
      "enabled" => Map.get(trigger, :enabled, false)
    }

    base
    |> maybe_put_string("cron_expression", Map.get(openfn, :cron))
    |> maybe_put_cron_cursor(Map.get(openfn, :cron_cursor), job_id_map)
    |> maybe_put_string("webhook_reply", Map.get(openfn, :webhook_reply))
    |> maybe_put_kafka(Map.get(openfn, :kafka))
  end

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_cron_cursor(map, nil, _job_id_map), do: map

  defp maybe_put_cron_cursor(map, cursor_step_id, job_id_map) do
    case Map.get(job_id_map, cursor_step_id) do
      nil -> map
      uuid -> Map.put(map, "cron_cursor_job_id", uuid)
    end
  end

  defp maybe_put_kafka(map, nil), do: map

  defp maybe_put_kafka(map, %{} = kafka) do
    config =
      kafka
      |> Enum.into(%{}, fn
        {:hosts, hosts} when is_list(hosts) ->
          # YAML carries hosts as ["host:port", ...]; the schema stores them
          # as [["host", "port"], ...].
          {"hosts",
           Enum.map(hosts, fn entry ->
             case String.split(to_string(entry), ":", parts: 2) do
               [h, p] -> [h, p]
               [h] -> [h]
             end
           end)}

        {k, v} ->
          {to_string(k), v}
      end)

    Map.put(map, "kafka_configuration", config)
  end

  # Walk every (source, target) pair from the canonical map and emit a
  # provisioner-shaped edge record with a UUID. Edges have no stable name, so
  # we key the existing-edge lookup on (source, target, condition_type) to
  # try to reuse UUIDs when re-importing the same project.
  defp build_edges_from_v2(
         triggers,
         steps,
         job_id_map,
         trigger_id_map,
         edge_index
       ) do
    trigger_edges =
      triggers
      |> Enum.flat_map(fn trigger ->
        next_to_pairs(Map.get(trigger, :next))
        |> Enum.map(fn {target, edge} ->
          source_uuid = Map.fetch!(trigger_id_map, trigger.id)
          target_uuid = Map.fetch!(job_id_map, target)
          condition_type = Map.get(edge, :condition, "always")

          edge_uuid =
            edge_lookup_uuid(
              edge_index,
              {:trigger, trigger.id, target, condition_type}
            )

          %{
            "id" => edge_uuid,
            "source_trigger_id" => source_uuid,
            "target_job_id" => target_uuid,
            "condition_type" => condition_type,
            "enabled" => not Map.get(edge, :disabled, false)
          }
          |> maybe_merge_js_expression(edge)
          |> maybe_put_string("condition_label", Map.get(edge, :label))
        end)
      end)

    job_edges =
      steps
      |> Enum.flat_map(fn step ->
        next_to_pairs(Map.get(step, :next))
        |> Enum.map(fn {target, edge} ->
          source_uuid = Map.fetch!(job_id_map, step.id)
          target_uuid = Map.fetch!(job_id_map, target)
          condition_type = Map.get(edge, :condition, "always")

          edge_uuid =
            edge_lookup_uuid(edge_index, {:job, step.id, target, condition_type})

          %{
            "id" => edge_uuid,
            "source_job_id" => source_uuid,
            "target_job_id" => target_uuid,
            "condition_type" => condition_type,
            "enabled" => not Map.get(edge, :disabled, false)
          }
          |> maybe_merge_js_expression(edge)
          |> maybe_put_string("condition_label", Map.get(edge, :label))
        end)
      end)

    trigger_edges ++ job_edges
  end

  defp next_to_pairs(nil), do: []

  defp next_to_pairs(target) when is_binary(target),
    do: [{target, %{condition: "always"}}]

  defp next_to_pairs(%{} = next_map) do
    Enum.map(next_map, fn {k, v} -> {to_string(k), v || %{}} end)
  end

  defp maybe_merge_js_expression(map, %{
         condition: "js_expression",
         expression: expr
       })
       when is_binary(expr) do
    Map.put(map, "condition_expression", expr)
  end

  defp maybe_merge_js_expression(map, _), do: map

  defp edge_lookup_uuid(edge_index, key) do
    Map.get(edge_index, key) || Ecto.UUID.generate()
  end

  defp drop_nil_keys(map) do
    map |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
  end

  # ── Existing-project index ──────────────────────────────────────────────

  # Build a (name → UUID) lookup over the existing project so cross-project
  # round-trips can preserve UUIDs by stable name. Only walked once at the
  # entry; per-record lookups hit the in-memory map.
  defp build_existing_index(nil) do
    %{
      project_id: nil,
      workflows: %{},
      collections: %{},
      credentials: %{}
    }
  end

  defp build_existing_index(%Project{} = project) do
    project = preload_existing_index(project)

    %{
      project_id: project.id,
      workflows: index_workflows(project.workflows || []),
      collections: index_collections(project.collections || []),
      credentials: index_credentials(project.project_credentials || [])
    }
  end

  defp index_workflows(workflows) do
    Enum.into(workflows, %{}, fn wf ->
      {wf.name, index_workflow(wf)}
    end)
  end

  defp index_workflow(wf) do
    %{
      id: wf.id,
      jobs: Enum.into(wf.jobs || [], %{}, fn j -> {hyphenate(j.name), j.id} end),
      triggers:
        Enum.into(wf.triggers || [], %{}, fn t ->
          {Atom.to_string(t.type), t.id}
        end),
      edges:
        Enum.into(wf.edges || [], %{}, fn e ->
          {build_edge_key(e, wf.jobs || [], wf.triggers || []), e.id}
        end)
    }
  end

  defp index_collections(collections) do
    Enum.into(collections, %{}, fn c -> {c.name, c.id} end)
  end

  defp index_credentials(project_credentials) do
    project_credentials
    |> Enum.flat_map(&credential_index_entry/1)
    |> Map.new()
  end

  defp credential_index_entry(%{credential: %{name: name} = cred, id: pc_id}) do
    email =
      case cred do
        %{user: %{email: e}} -> e
        _ -> nil
      end

    [{name, %{id: pc_id, owner_email: email}}]
  end

  defp credential_index_entry(_), do: []

  defp preload_existing_index(%Project{} = project) do
    if existing_index_loaded?(project) do
      project
    else
      Lightning.Repo.preload(project,
        project_credentials: [credential: :user],
        collections: [],
        workflows: [:jobs, :triggers, :edges]
      )
    end
  end

  defp existing_index_loaded?(%Project{} = p) do
    not match?(%Ecto.Association.NotLoaded{}, p.workflows) and
      not match?(%Ecto.Association.NotLoaded{}, p.collections) and
      not match?(%Ecto.Association.NotLoaded{}, p.project_credentials)
  end

  defp build_edge_key(edge, jobs, triggers) do
    target_key =
      jobs
      |> Enum.find_value(fn j ->
        if j.id == edge.target_job_id, do: hyphenate(j.name)
      end)

    cond do
      not is_nil(edge.source_trigger_id) ->
        trigger_key =
          triggers
          |> Enum.find_value(fn t ->
            if t.id == edge.source_trigger_id, do: Atom.to_string(t.type)
          end)

        {:trigger, trigger_key, target_key,
         edge.condition_type && Atom.to_string(edge.condition_type)}

      not is_nil(edge.source_job_id) ->
        source_key =
          jobs
          |> Enum.find_value(fn j ->
            if j.id == edge.source_job_id, do: hyphenate(j.name)
          end)

        {:job, source_key, target_key,
         edge.condition_type && Atom.to_string(edge.condition_type)}

      true ->
        :unknown
    end
  end

  defp hyphenate(string) when is_binary(string),
    do: String.replace(string, " ", "-")

  defp hyphenate(other), do: other

  defp lookup_or_mint(index, [:collections, name]) do
    Map.get(index.collections, name) || Ecto.UUID.generate()
  end
end
