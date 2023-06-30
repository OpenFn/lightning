defmodule Lightning.ExportUtils do
  @moduledoc """
  Module that expose a function generating a complete and valid yaml string
  from a project and its workflows.
  """

  alias Lightning.Repo

  alias Lightning.{
    Projects,
    Workflows,
    ExportUtilsNum
  }

  defp job_to_treenode(job) do
    job_name = job.name |> String.replace(" ", "-")
    %{body: credential_body} = job.credential || %{body: %{}}

    %{
      id: job.id,
      name: job_name,
      node_type: :job,
      adaptor: job.adaptor,
      body: job.body,
      credential: credential_body,
      globals: [],
      enabled: job.enabled
    }
  end

  defp trigger_to_treenode({num, trigger}) do
    {:ok, string_no} = ExportUtilsNum.Number.to_string(num, format: :spellout)

    %{
      id: trigger.id,
      name: "trigger-" <> string_no,
      node_type: :trigger,
      type: Atom.to_string(trigger.type)
    }
  end

  defp edge_to_treenode(%{source_job_id: nil} = edge, triggers) do
    edge = Repo.preload(edge, [:source_trigger, :target_job])
    trigger_name = edge.source_trigger.type |> Atom.to_string()
    target_name = edge.target_job.name |> String.replace(" ", "-")

    %{
      name: "#{trigger_name}->#{target_name}",
      source_trigger: find_trigger_name(edge, triggers),
      target_job: target_name,
      condition: edge.condition,
      node_type: :edge
    }
  end

  defp edge_to_treenode(%{source_trigger_id: nil} = edge, _unused_triggers) do
    edge = Repo.preload(edge, [:source_job, :target_job])
    source_job = edge.source_job.name |> String.replace(" ", "-")
    target_job = edge.target_job.name |> String.replace(" ", "-")

    %{
      name: "#{source_job}->#{target_job}",
      source_job: source_job,
      target_job: target_job,
      condition: edge.condition,
      node_type: :edge
    }
  end

  defp find_trigger_name(edge, triggers) do
    [trigger] = Enum.filter(triggers, fn t -> t.id == edge.source_trigger_id end)

    trigger.name
  end

  defp handle_bitstring(k, v, i) do
    case(k === :body) do
      true ->
        indented_expression =
          String.split(v, "\n")
          |> Enum.map_join("\n", fn line -> "#{i}  #{line}" end)

        "body: |\n#{indented_expression}"

      false ->
        "#{k}: #{v}"
    end
  end

  defp is_of_type(map, type) do
    Map.has_key?(map, :node_type) and map.node_type == type
  end

  defp pick_and_sort(map) do
    ordering_map = %{
      project: [:name, :globals, :workflows],
      workflow: [:name, :jobs, :triggers, :edges],
      job: [:name, :adaptor, :enabled, :credential, :globals, :body],
      trigger: [:type],
      edge: [:source_trigger, :source_job, :target_job]
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

  defp handle_input(key, value, indentation) when is_bitstring(value) do
    "#{indentation}#{handle_bitstring(key, value, indentation)}"
  end

  defp handle_input(key, value, indentation) when is_number(value) do
    "#{indentation}#{key}: #{value}"
  end

  defp handle_input(key, value, indentation) when is_boolean(value) do
    "#{indentation}#{key}: #{Atom.to_string(value)}"
  end

  defp handle_input(key, value, indentation) when value in [%{}, []] do
    "#{indentation}#{key}:"
  end

  defp handle_input(key, value, indentation) when is_map(value) do
    "#{indentation}#{key}:\n#{to_new_yaml(value, "#{indentation}  ")}"
  end

  defp handle_input(key, value, indentation) when is_list(value) do
    "#{indentation}#{key}:\n#{Enum.map_join(value, "\n", fn map -> cond do
        is_of_type(map, :workflow) -> "#{indentation}  #{map.name}:\n#{to_new_yaml(map, "#{indentation}    ")}"
        is_of_type(map, :job) -> "#{indentation}  #{map.name}:\n#{to_new_yaml(map, "#{indentation}   ")}"
        is_of_type(map, :edge) -> "#{indentation}  #{map.name}:\n#{to_new_yaml(map, "#{indentation}   ")}"
        is_of_type(map, :trigger) -> "#{indentation}  #{map.name}:\n#{to_new_yaml(map, "#{indentation}   ")}"
        true -> nil
      end end)}"
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
      Enum.reduce(workflows, %{}, fn workflow, acc ->
        ytree = build_workflow_yaml_tree(workflow)
        Map.put(acc, String.replace(workflow.name, " ", "-"), ytree)
      end)

    %{
      name: project.name,
      node_type: :project,
      globals: [],
      workflows: workflows_map
    }
  end

  defp build_workflow_yaml_tree(workflow) do
    jobs = Enum.map(workflow.jobs, fn j -> job_to_treenode(j) end)
    numbered_triggers = Enum.zip(1..length(workflow.triggers), workflow.triggers)
    triggers = Enum.map(numbered_triggers, fn t -> trigger_to_treenode(t) end)
    edges = Enum.map(workflow.edges, fn e -> edge_to_treenode(e, triggers) end)

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
