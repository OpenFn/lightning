defmodule LightningWeb.API.ProvisioningJSON do
  @moduledoc false

  import LightningWeb.CoreComponents, only: [translate_error: 1]
  import Ecto.Changeset

  alias Lightning.Collections.Collection
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.WorkflowVersions
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  def render("create.json", %{project: project, conn: _conn}) do
    %{"data" => as_json(project)}
  end

  def error(%{changeset: %Ecto.Changeset{} = changeset}) do
    %{errors: traverse_provision_errors(changeset)}
  end

  def as_json(%Project{} = project) do
    Ecto.embedded_dump(project, :json)
    |> Map.delete(:version_history)
    |> Map.put(
      :workflows,
      project.workflows
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
    |> Map.put(
      :project_credentials,
      project.project_credentials
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
    |> Map.put(
      :collections,
      project.collections
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
  end

  def as_json(%module{} = workflow_or_snapshot)
      when module in [Workflow, Snapshot] do
    workflow_id =
      if module == Workflow do
        workflow_or_snapshot.id
      else
        workflow_or_snapshot.workflow_id
      end

    base_map =
      workflow_or_snapshot
      |> Ecto.embedded_dump(:json)
      |> Map.take(
        ~w(id name inserted_at updated_at deleted_at lock_version concurrency version_history)a
      )
      |> Map.put(:id, workflow_id)
      |> Map.put(
        :jobs,
        workflow_or_snapshot.jobs
        |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
        |> Enum.map(&as_json/1)
      )
      |> Map.put(
        :triggers,
        workflow_or_snapshot.triggers
        |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
        |> Enum.map(&as_json/1)
      )
      |> Map.put(
        :edges,
        workflow_or_snapshot.edges
        |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
        |> Enum.map(&as_json/1)
      )

    # snapshots don't have version_history
    if module == Workflow do
      version_history =
        case Map.get(base_map, :version_history) do
          nil -> WorkflowVersions.history_for(workflow_or_snapshot)
          [] -> WorkflowVersions.history_for(workflow_or_snapshot)
          history -> history
        end

      Map.put(base_map, :version_history, version_history)
    else
      base_map
    end
  end

  def as_json(%module{} = job) when module in [Job, Snapshot.Job] do
    Ecto.embedded_dump(job, :json)
    |> Map.take(~w(id adaptor body name project_credential_id)a)
  end

  def as_json(%module{} = trigger) when module in [Trigger, Snapshot.Trigger] do
    trigger = Ecto.embedded_dump(trigger, :json)

    kafka_configuration =
      trigger.kafka_configuration &&
        Map.take(
          trigger.kafka_configuration,
          ~w(hosts topics initial_offset_reset_policy connect_timeout)a
        )

    trigger
    |> Map.take(~w(id type cron_expression enabled)a)
    |> Map.put(:kafka_configuration, kafka_configuration)
    |> drop_keys_with_nil_value()
  end

  def as_json(%module{} = edge) when module in [Edge, Snapshot.Edge] do
    Ecto.embedded_dump(edge, :json)
    |> Map.take(~w(
      id enabled source_job_id source_trigger_id
      condition_type condition_label condition_expression target_job_id
    )a)
    |> drop_keys_with_nil_value()
  end

  def as_json(%ProjectCredential{} = project_credential) do
    %{
      id: project_credential.id,
      name: project_credential.credential.name,
      owner: project_credential.credential.user.email
    }
  end

  def as_json(%Collection{} = collection) do
    %{id: collection.id, name: collection.name}
  end

  defp drop_keys_with_nil_value(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end

  # inspired by: https://github.com/elixir-ecto/ecto/blob/v3.11.2/lib/ecto/changeset.ex#L4037
  defp traverse_provision_errors(%Ecto.Changeset{errors: errors} = changeset) do
    errors
    |> Enum.reverse()
    |> merge_keyword_keys()
    |> merge_related_keys(changeset)
  end

  defp merge_keyword_keys(keyword_list) do
    Enum.reduce(keyword_list, %{}, fn {key, val}, acc ->
      val = translate_error(val)
      Map.update(acc, key, [val], &[val | &1])
    end)
  end

  defp merge_related_keys(
         map,
         %Ecto.Changeset{changes: changes, data: %schema_module{}} = changeset
       ) do
    fields =
      schema_module.__schema__(:associations) ++
        schema_module.__schema__(:embeds)

    Enum.reduce(fields, map, fn
      :workflows, acc ->
        traverse_field_errors(acc, changes, :workflows, fn workflow_changeset ->
          get_field(workflow_changeset, :name)
        end)

      :triggers, acc ->
        traverse_field_errors(acc, changes, :triggers, fn trigger_changeset ->
          get_field(trigger_changeset, :type)
        end)

      :jobs, acc ->
        traverse_field_errors(acc, changes, :jobs, fn job_changeset ->
          get_field(job_changeset, :name)
        end)

      :edges, acc ->
        traverse_field_errors(acc, changes, :edges, fn edge_changeset ->
          source_trigger_id = get_field(edge_changeset, :source_trigger_id)
          source_job_id = get_field(edge_changeset, :source_job_id)
          target_job_id = get_field(edge_changeset, :target_job_id)
          jobs = get_assoc(changeset, :jobs, :struct)
          triggers = get_assoc(changeset, :triggers, :struct)

          source_name =
            case {source_trigger_id, source_job_id} do
              {nil, nil} ->
                nil

              {nil, job_id} ->
                job = find_item_by_id(jobs, job_id)
                job && job.name

              {trigger_id, nil} ->
                trigger = find_item_by_id(triggers, trigger_id)
                trigger && trigger.type
            end

          target_name =
            if target_job_id do
              job = find_item_by_id(jobs, target_job_id)
              job && job.name
            end

          "#{source_name}->#{target_name}"
        end)

      field, acc ->
        traverse_field_errors(acc, changes, field, fn _ -> field end)
    end)
  end

  defp traverse_field_errors(acc, changes, field, child_name_func)
       when is_function(child_name_func, 1) do
    changesets =
      case Map.get(changes, field) do
        %{} = change ->
          [change]

        changes ->
          changes
      end

    if changesets do
      child = traverse_nested_changesets(changesets, child_name_func)

      if child == %{} do
        acc
      else
        Map.put(acc, field, child)
      end
    else
      acc
    end
  end

  defp traverse_nested_changesets(changesets, child_name_func) do
    Enum.reduce(changesets, %{}, fn changeset, acc ->
      child = traverse_provision_errors(changeset)

      if child == %{} do
        acc
      else
        child_name = changeset |> child_name_func.() |> to_string()
        Map.put(acc, child_name, child)
      end
    end)
  end

  defp find_item_by_id(items, id) do
    Enum.find(items, fn item -> item.id == id end)
  end
end
