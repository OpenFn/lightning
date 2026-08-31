defmodule Lightning.Workflows.Spec do
  @moduledoc """
  Lightning's hand-writable workflow format, and its translation into a
  provisioning document.

  This is the same format the collaborative editor imports and exports
  (`assets/js/yaml/util.ts`) and that workflow templates are written in:
  `jobs`, `triggers` and `edges` are **maps keyed by slug**, and they
  reference each other by those keys rather than by id.

      name: My Workflow
      jobs:
        transform-data:
          name: Transform data
          adaptor: "@openfn/language-common@latest"
          body: fn(state => state);
      triggers:
        webhook:
          type: webhook
          enabled: true
      edges:
        webhook->transform-data:
          source_trigger: webhook
          target_job: transform-data
          condition_type: always
          enabled: true

  `to_document/2` resolves those key references into the id-based document
  `Lightning.Projects.Provisioner` consumes (`jobs`, `triggers` and `edges`
  as lists, wired together with `source_job_id`, `source_trigger_id`,
  `target_job_id`, ...).

  It is the Elixir counterpart of `convertWorkflowSpecToState` in
  `assets/js/yaml/util.ts` and validates against the very same JSON Schema
  (`assets/js/yaml/schema/workflow-spec.json`, read at compile time), so a
  workflow that the editor accepts is a workflow this accepts, and vice
  versa.

  ## Options

    * `:id_fun` - `(kind, key -> uuid)` used to mint ids for records that
      don't carry an explicit `id`, where `kind` is `:workflow`, `:job`,
      `:trigger` or `:edge` and `key` is the record's key in the spec (the
      workflow's `name`, for `:workflow`). Defaults to random UUIDs, like the
      editor does; callers that need idempotent re-runs (see
      `Lightning.Kickstart`) pass a deterministic function.

    * `:credentials` - `%{credential_name => project_credential_id}`, used to
      resolve a job's `credential` key into `project_credential_id`. Jobs
      referencing a credential that isn't in the map are an error.

  ## Not covered

  `pos` is accepted (it's part of the format, and the editor round-trips it)
  but not carried into the document: the provisioner has no way to set node
  positions. Kafka trigger configuration isn't part of the format yet, in
  either implementation.
  """

  alias ExJsonSchema.Validator

  # Single source of truth, shared with the TypeScript implementation. Read at
  # compile time so releases don't need `assets/` on disk.
  @schema_path Path.expand(
                 "../../../assets/js/yaml/schema/workflow-spec.json",
                 __DIR__
               )
  @external_resource @schema_path
  @raw_schema File.read!(@schema_path)

  @type spec :: %{String.t() => any()}
  @type kind :: :workflow | :job | :trigger | :edge
  @type id_fun :: (kind(), String.t() | nil -> Ecto.UUID.t())

  @doc """
  Validate a spec against the workflow-spec JSON Schema (plus the duplicate
  job name check the editor also applies).
  """
  @spec validate(spec()) :: :ok | {:error, String.t()}
  def validate(spec) when is_map(spec) do
    case Validator.validate(schema(), spec) do
      :ok -> validate_unique_job_names(spec)
      {:error, errors} -> {:error, format_schema_errors(errors)}
    end
  end

  def validate(other) do
    {:error, "Expected a workflow spec map, got: #{inspect(other)}"}
  end

  @doc """
  Convert a workflow spec into a provisioning document.

  See the module docs for the available options.
  """
  @spec to_document(spec(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def to_document(spec, opts \\ []) do
    id_fun = Keyword.get(opts, :id_fun, &random_id/2)
    credentials = Keyword.get(opts, :credentials, %{})

    with :ok <- validate(spec),
         {:ok, jobs} <- build_jobs(spec, id_fun, credentials),
         {:ok, triggers} <- build_triggers(spec, id_fun, jobs),
         {:ok, edges} <- build_edges(spec, id_fun, jobs, triggers) do
      {:ok,
       %{
         "id" => spec["id"] || id_fun.(:workflow, spec["name"]),
         "name" => spec["name"],
         "jobs" => documents(jobs),
         "triggers" => documents(triggers),
         "edges" => edges
       }}
    end
  end

  @doc """
  Same as `to_document/2`, raising on an invalid spec.
  """
  @spec to_document!(spec(), keyword()) :: map()
  def to_document!(spec, opts \\ []) do
    case to_document(spec, opts) do
      {:ok, document} -> document
      {:error, message} -> raise message
    end
  end

  defp schema do
    case :persistent_term.get({__MODULE__, :schema}, nil) do
      nil ->
        root = @raw_schema |> Jason.decode!() |> ExJsonSchema.Schema.resolve()
        :persistent_term.put({__MODULE__, :schema}, root)
        root

      root ->
        root
    end
  end

  defp random_id(_kind, _key), do: Ecto.UUID.generate()

  # Duplicate keys are impossible (they're map keys), but two jobs can still
  # declare the same `name`, which the database rejects with an opaque unique
  # constraint error. The editor checks this too (`DuplicateJobNameError`).
  defp validate_unique_job_names(spec) do
    spec
    |> entries("jobs")
    |> Enum.map(fn {_key, job} -> job["name"] end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> case do
      [] ->
        :ok

      duplicates ->
        names = Enum.map_join(duplicates, ", ", &inspect(elem(&1, 0)))
        {:error, "Duplicate job name(s) in workflow spec: #{names}"}
    end
  end

  # Spec maps are unordered; sorting by key keeps the generated document (and
  # so the manifest, and any diff of it) stable across runs.
  defp entries(spec, key) do
    spec |> Map.get(key) |> Kernel.||(%{}) |> Enum.sort_by(&elem(&1, 0))
  end

  defp documents(records) do
    Enum.map(records, fn {_key, %{document: document}} -> document end)
  end

  defp build_jobs(spec, id_fun, credentials) do
    map_ok(entries(spec, "jobs"), fn {key, job} ->
      id = job["id"] || id_fun.(:job, key)

      with {:ok, document} <- job_document(job, id, key, credentials) do
        {:ok, {key, %{id: id, name: job["name"], document: document}}}
      end
    end)
  end

  defp job_document(job, id, key, credentials) do
    document = %{
      "id" => id,
      "name" => job["name"],
      "adaptor" => job["adaptor"],
      "body" => job["body"]
    }

    case job["credential"] do
      nil ->
        {:ok, document}

      name ->
        case Map.fetch(credentials, name) do
          {:ok, project_credential_id} ->
            {:ok,
             Map.put(document, "project_credential_id", project_credential_id)}

          :error ->
            {:error,
             ~s(Job "#{key}" references credential #{inspect(name)}, which ) <>
               "isn't available to this workflow" <>
               known(Map.keys(credentials))}
        end
    end
  end

  defp build_triggers(spec, id_fun, jobs) do
    map_ok(entries(spec, "triggers"), fn {key, trigger} ->
      id = trigger["id"] || id_fun.(:trigger, key)

      with {:ok, document} <- trigger_document(trigger, id, key, jobs) do
        {:ok, {key, %{id: id, type: trigger["type"], document: document}}}
      end
    end)
  end

  defp trigger_document(trigger, id, key, jobs) do
    document =
      %{"id" => id, "type" => trigger["type"], "enabled" => trigger["enabled"]}
      |> copy_declared(trigger, "cron_expression")
      |> copy_declared(trigger, "webhook_reply")
      |> copy_declared(trigger, "webhook_response_config")

    resolve_cron_cursor_job(document, trigger, key, jobs)
  end

  defp resolve_cron_cursor_job(document, trigger, key, jobs) do
    case Map.fetch(trigger, "cron_cursor_job") do
      :error ->
        {:ok, document}

      {:ok, nil} ->
        {:ok, Map.put(document, "cron_cursor_job_id", nil)}

      {:ok, job_key} ->
        with {:ok, job} <-
               fetch_record(jobs, job_key, :job, ~s(Trigger "#{key}")) do
          {:ok, Map.put(document, "cron_cursor_job_id", job.id)}
        end
    end
  end

  defp build_edges(spec, id_fun, jobs, triggers) do
    with {:ok, edges} <-
           map_ok(entries(spec, "edges"), fn {key, edge} ->
             id = edge["id"] || id_fun.(:edge, key)

             with {:ok, document} <- edge_document(edge, id, key, jobs, triggers) do
               {:ok, {key, %{id: id, document: document}}}
             end
           end) do
      {:ok, documents(edges)}
    end
  end

  defp edge_document(edge, id, key, jobs, triggers) do
    context = ~s(Edge "#{key}")

    document =
      %{
        "id" => id,
        "condition_type" => edge["condition_type"],
        "enabled" => edge["enabled"]
      }
      |> copy_declared(edge, "condition_label")
      |> copy_declared(edge, "condition_expression")

    with {:ok, target} <- fetch_record(jobs, edge["target_job"], :job, context),
         {:ok, document} <-
           resolve_edge_source(document, edge, context, jobs, triggers) do
      {:ok, Map.put(document, "target_job_id", target.id)}
    end
  end

  defp resolve_edge_source(document, edge, context, jobs, triggers) do
    case {edge["source_trigger"], edge["source_job"]} do
      {nil, nil} ->
        {:error, "#{context} needs a source_trigger or a source_job"}

      {trigger_key, nil} ->
        with {:ok, trigger} <-
               fetch_record(triggers, trigger_key, :trigger, context) do
          {:ok, Map.put(document, "source_trigger_id", trigger.id)}
        end

      {nil, job_key} ->
        with {:ok, job} <- fetch_record(jobs, job_key, :job, context) do
          {:ok, Map.put(document, "source_job_id", job.id)}
        end

      {_trigger_key, _job_key} ->
        {:error,
         "#{context} declares both a source_trigger and a source_job — " <>
           "an edge can only have one source"}
    end
  end

  defp fetch_record(records, key, kind, context) do
    case List.keyfind(records, key, 0) do
      {^key, record} ->
        {:ok, record}

      nil ->
        {:error,
         "#{context} references #{kind} #{inspect(key)}, which isn't " <>
           ~s(defined under the spec's "#{kind}s") <>
           known(Enum.map(records, &elem(&1, 0)))}
    end
  end

  defp known([]), do: ""
  defp known(keys), do: " (known: #{Enum.map_join(keys, ", ", &inspect/1)})"

  # Only carry over keys the spec actually declares, so an omitted field means
  # "leave it as it is" rather than "reset it to nil".
  defp copy_declared(document, spec, key) do
    case Map.fetch(spec, key) do
      {:ok, value} -> Map.put(document, key, value)
      :error -> document
    end
  end

  defp map_ok(entries, fun) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case fun.(entry) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  # ExJsonSchema paths point at the offending key itself (`#/triggers/webhook/
  # webook_replyy`), so a typo is named without further help.
  defp format_schema_errors(errors) do
    details =
      Enum.map_join(errors, "; ", fn {message, path} -> "#{path} #{message}" end)

    "Invalid workflow spec: #{details}"
  end
end
