defmodule LightningWeb.API.ProvisioningJSON do
  @moduledoc false

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  import LightningWeb.CoreComponents, only: [translate_error: 1]
  import Ecto.Changeset

  def render("create.json", %{project: project, conn: _conn}) do
    %{"data" => as_json(project)}
  end

  def error(%{changeset: %Ecto.Changeset{} = changeset}) do
    %{errors: traverse_provision_errors(changeset)}
  end

  def as_json(%Project{} = project) do
    Ecto.embedded_dump(project, :json)
    |> Map.put(
      "workflows",
      project.workflows
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
  end

  def as_json(%Workflow{} = workflow) do
    Ecto.embedded_dump(workflow, :json)
    |> Map.put(
      "jobs",
      workflow.jobs
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
    |> Map.put(
      "triggers",
      workflow.triggers
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
    |> Map.put(
      "edges",
      workflow.edges
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
  end

  def as_json(%Job{} = job) do
    Ecto.embedded_dump(job, :json)
    |> Map.take(~w(id adaptor body name)a)
  end

  def as_json(%Trigger{} = trigger) do
    Ecto.embedded_dump(trigger, :json)
    |> Map.take(~w(id type cron_expression enabled)a)
    |> drop_keys_with_nil_value()
  end

  def as_json(%Edge{} = edge) do
    Ecto.embedded_dump(edge, :json)
    |> Map.take(~w(
      id enabled source_job_id source_trigger_id
      condition_type condition_label condition_expression target_job_id
    )a)
    |> drop_keys_with_nil_value()
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
