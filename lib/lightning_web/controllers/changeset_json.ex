defmodule LightningWeb.ChangesetJSON do
  @moduledoc """
  Renders changesets as JSON.
  """

  import LightningWeb.CoreComponents, only: [translate_error: 1]
  import Ecto.Changeset

  def error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(
      changeset,
      &translate_error/1
    )
  end

  def error(%{changeset: %Ecto.Changeset{} = changeset}) do
    %{errors: error(changeset)}
  end

  def provisioning_error(%{changeset: %Ecto.Changeset{} = changeset}) do
    %{errors: traverse_provision_errors(changeset)}
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
