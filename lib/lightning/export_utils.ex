defmodule Lightning.ExportUtils do
  @moduledoc """
  Module that expose a function generating a complete and valid yaml string
  from a project and its workflows.
  """

  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.Workflows

  defp hyphenate(string) when is_binary(string) do
    string |> String.replace(" ", "-")
  end

  defp hyphenate(other), do: other

  defp job_to_treenode(job) do
    %{
      # The identifier here for our YAML reducer will be the hyphenated name
      id: hyphenate(job.name),
      name: job.name,
      node_type: :job,
      adaptor: job.adaptor,
      body: job.body,
      credential: nil,
      globals: []
    }
  end

  defp trigger_to_treenode(trigger) do
    base = %{
      id: trigger.id,
      enabled: trigger.enabled,
      name: Atom.to_string(trigger.type),
      node_type: :trigger,
      type: Atom.to_string(trigger.type)
    }

    if trigger.type == :cron,
      do: Map.put(base, :cron_expression, trigger.cron_expression),
      else: base
  end

  defp edge_to_treenode(%{source_job_id: nil} = edge, triggers) do
    edge = Repo.preload(edge, [:source_trigger, :target_job])
    trigger_name = edge.source_trigger.type |> Atom.to_string()
    target_job = edge.target_job.name |> hyphenate()

    %{
      name: "#{trigger_name}->#{target_job}",
      source_trigger: find_trigger_name(edge, triggers)
    }
    |> merge_edge_common_fields(edge)
  end

  defp edge_to_treenode(%{source_trigger_id: nil} = edge, _unused_triggers) do
    edge = Repo.preload(edge, [:source_job, :target_job])
    source_job = edge.source_job.name |> hyphenate()
    target_job = edge.target_job.name |> hyphenate()

    %{
      name: "#{source_job}->#{target_job}",
      source_job: source_job
    }
    |> merge_edge_common_fields(edge)
  end

  defp merge_edge_common_fields(json, edge) do
    target_job = edge.target_job.name |> hyphenate()

    json
    |> Map.merge(%{
      target_job: target_job,
      condition_type: edge.condition_type |> Atom.to_string(),
      enabled: edge.enabled,
      node_type: :edge
    })
    |> then(fn map ->
      if edge.condition_type == :js_expression do
        Map.merge(map, %{
          condition_expression: edge.condition_expression,
          condition_label: edge.condition_label
        })
      else
        map
      end
    end)
  end

  defp find_trigger_name(edge, triggers) do
    [trigger] = Enum.filter(triggers, fn t -> t.id == edge.source_trigger_id end)

    trigger.name
  end

  defp pick_and_sort(map) do
    ordering_map = %{
      project: [:name, :description, :credentials, :globals, :workflows],
      workflow: [:name, :jobs, :triggers, :edges],
      job: [:name, :adaptor, :credential, :globals, :body],
      trigger: [:type, :cron_expression, :enabled],
      edge: [
        :source_trigger,
        :source_job,
        :target_job,
        :condition_type,
        :condition_label,
        :condition_expression,
        :enabled
      ]
    }

    map
    |> Enum.filter(fn {key, _value} ->
      if Map.has_key?(map, :node_type) do
        ordering_map[map.node_type]
        |> Enum.member?(key)
      else
        true
      end
    end)
    |> Enum.sort_by(
      fn {key, _value} ->
        if Map.has_key?(map, :node_type) do
          olist = ordering_map[map.node_type]

          olist
          |> Enum.find_index(&(&1 == key))
        end
      end,
      :asc
    )
  end

  defp handle_binary(k, v, i) do
    case k do
      :body ->
        indented_expression =
          String.split(v, "\n")
          |> Enum.map_join("\n", fn line -> "#{i}  #{line}" end)

        "body: |\n#{indented_expression}"

      :adaptor ->
        "#{k}: '#{v}'"

      :cron_expression ->
        "#{k}: '#{v}'"

      _ ->
        "#{k}: #{v}"
    end
  end

  defp handle_input(key, value, indentation) when is_binary(value) do
    "#{indentation}#{handle_binary(key, value, indentation)}"
  end

  defp handle_input(key, value, indentation) when is_number(value) do
    "#{indentation}#{key}: #{value}"
  end

  defp handle_input(key, value, indentation) when is_boolean(value) do
    "#{indentation}#{key}: #{Atom.to_string(value)}"
  end

  defp handle_input(key, value, indentation) when value in [%{}, [], nil] do
    "#{indentation}# #{key}:"
  end

  defp handle_input(key, value, indentation) when is_map(value) do
    "#{indentation}#{hyphenate(key)}:\n#{to_new_yaml(value, "#{indentation}  ")}"
  end

  defp handle_input(key, value, indentation) when is_list(value) do
    "#{indentation}#{hyphenate(key)}:\n#{Enum.map_join(value, "\n", fn map -> "#{indentation}  #{hyphenate(map.name)}:\n#{to_new_yaml(map, "#{indentation}    ")}" end)}"
  end

  defp to_new_yaml(map, indentation \\ "") do
    map
    |> pick_and_sort()
    |> Enum.map(fn {key, value} ->
      handle_input(key, value, indentation)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp to_workflow_yaml_tree(flow_map, workflow) do
    %{
      name: workflow.name,
      jobs: flow_map.jobs,
      triggers: flow_map.triggers,
      edges: flow_map.edges,
      node_type: :workflow
    }
  end

  def build_yaml_tree(workflows, project) do
    workflows_map =
      workflows
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.reduce(%{}, fn workflow, acc ->
        ytree = build_workflow_yaml_tree(workflow)
        Map.put(acc, hyphenate(workflow.name), ytree)
      end)

    %{
      name: project.name,
      description: project.description,
      node_type: :project,
      globals: [],
      workflows: workflows_map,
      credentials: []
    }
  end

  defp build_workflow_yaml_tree(workflow) do
    jobs =
      workflow.jobs
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn j -> job_to_treenode(j) end)

    triggers =
      workflow.triggers
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn t -> trigger_to_treenode(t) end)

    edges =
      workflow.edges
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn e -> edge_to_treenode(e, triggers) end)

    flow_map = %{jobs: jobs, edges: edges, triggers: triggers}

    flow_map
    |> to_workflow_yaml_tree(workflow)
  end

  def generate_new_yaml(project_id) do
    project = Projects.get_project!(project_id)

    yaml =
      project
      |> Workflows.get_workflows_for()
      |> build_yaml_tree(project)
      |> to_new_yaml()

    {:ok, yaml}
  end
end
