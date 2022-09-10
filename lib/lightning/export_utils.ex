defmodule Lightning.ExportUtils do
  alias Lightning.{
    Projects,
    Workflows
  }

  defp job_to_treenode(job) do
    trigger = job.trigger
    parent_job = trigger.upstream_job
    job_name = job.name |> String.replace(" ", "-")
    %{body: credential_body} = job.credential || %{body: %{}}

    IO.inspect(trigger.type)

    {parent_id, trigger} =
      case trigger.type do
        :webhook ->
          {nil, "webhook"}

        :cron ->
          {nil, %{cron: trigger.cron}}

        :on_job_success ->
          {parent_job.id,
           %{"on-success": parent_job.name |> String.replace(" ", "-")}}

        :on_job_failure ->
          {parent_job.id,
           %{"on-fail": parent_job.name |> String.replace(" ", "-")}}
      end

    %{
      id: job.id,
      name: job_name,
      node_type: :job,
      parent_id: parent_id,
      trigger: trigger,
      adaptor: job.adaptor,
      body: job.body,
      credential: credential_body,
      globals: [],
      enabled: job.enabled
    }
  end

  defp node_list_to_tree(flat_node_list) do
    groups = Enum.group_by(flat_node_list, & &1.parent_id)

    Enum.map(groups[nil], &associate_children(&1, groups))
  end

  defp associate_children(node, groups) do
    children = Enum.map(groups[node.id] || [], &associate_children(&1, groups))
    Map.put(node, :jobs, children)
  end

  defp flatten_job_descendants(acc, job_node) do
    {children, job} = Map.pop(job_node, :jobs)

    Enum.reduce(children, acc ++ [job], fn child, ac ->
      flatten_job_descendants(ac, child)
    end)
  end

  defp handle_bitstring(k, v, i) do
    case(k === :body) do
      true ->
        indented_expression =
          String.split(v, "\n")
          |> Enum.map(fn line -> "#{i}  #{line}" end)
          |> Enum.join("\n")

        "body: >\n#{indented_expression}"

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
      workflow: [:jobs],
      job: [:trigger, :adaptor, :enabled, :credential, :globals, :body]
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
          |> Enum.find_index(fn okey -> key == okey end)
        end
      end,
      :asc
    )
  end

  defp to_new_yaml(map, indentation \\ "") do
    map
    |> pick_and_sort()
    |> Enum.map(fn {key, value} ->
      cond do
        is_bitstring(value) ->
          "#{indentation}#{handle_bitstring(key, value, indentation)}"

        is_number(value) ->
          "#{indentation}#{key}: #{value}"

        is_boolean(value) ->
          "#{indentation}#{key}: #{Atom.to_string(value)}"

        value == %{} ->
          "#{indentation}#{key}:"

        is_map(value) ->
          "#{indentation}#{key}:\n#{to_new_yaml(value, "#{indentation}  ")}"

        value == [] ->
          "#{indentation}#{key}:"

        is_list(value) ->
          "#{indentation}#{key}:\n#{Enum.map(value, fn map -> cond do
              is_of_type(map, :workflow) -> "#{indentation}  #{map.name}:\n#{to_new_yaml(map, "#{indentation}    ")}"
              is_of_type(map, :job) -> "#{indentation}  #{map.name}:\n#{to_new_yaml(map, "#{indentation}    ")}"
              true -> nil
            end end) |> Enum.join("\n")}"

        true ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp to_workflow_yaml_tree(tree, workflow) do
    Enum.reduce(tree, [], fn root_job_node, acc ->
      flat = flatten_job_descendants([], root_job_node)

      acc ++
        [
          %{
            name: workflow.name,
            jobs: flat,
            node_type: :workflow
          }
        ]
    end)
  end

  def build_yaml_tree(workflows, project) do
    workflows_map =
      Enum.reduce(workflows, %{}, fn workflow, acc ->
        [ytree] = build_workflow_yaml_tree(workflow)
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
    Enum.map(workflow.jobs, fn j -> job_to_treenode(j) end)
    |> node_list_to_tree()
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
