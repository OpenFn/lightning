defmodule Lightning.ExportUtils do
  @moduledoc """
  Module that expose a function generating a complete and valid yaml string
  from a project and its workflows.
  """

  alias Lightning.Projects
  alias Lightning.Workflows
  alias Lightning.Workflows.Snapshot

  @ordering_map %{
    project: [:name, :description, :credentials, :globals, :workflows],
    credential: [:name, :owner],
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

  @special_keys Enum.flat_map(@ordering_map, fn {node_key, child_keys} ->
                  [node_key | child_keys]
                end)

  defp hyphenate(string) when is_binary(string) do
    string |> String.replace(" ", "-")
  end

  defp hyphenate(other), do: other

  defp job_to_treenode(job, project_credentials) do
    project_credential =
      Enum.find(project_credentials, fn pc ->
        pc.id == job.project_credential_id
      end)

    %{
      # The identifier here for our YAML reducer will be the hyphenated name
      id: hyphenate(job.name),
      name: job.name,
      node_type: :job,
      adaptor: job.adaptor,
      body: job.body,
      credential:
        project_credential && project_credential_key(project_credential)
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

  defp edge_to_treenode(%{source_job_id: nil} = edge, triggers, jobs) do
    source_trigger =
      Enum.find(triggers, fn t -> t.id == edge.source_trigger_id end)

    target_job = Enum.find(jobs, fn j -> j.id == edge.target_job_id end)
    trigger_name = to_string(source_trigger.type)
    target_job_name = hyphenate(target_job.name)

    %{
      name: "#{trigger_name}->#{target_job_name}",
      source_trigger: trigger_name
    }
    |> merge_edge_common_fields(edge, target_job)
  end

  defp edge_to_treenode(%{source_trigger_id: nil} = edge, _triggers, jobs) do
    target_job = Enum.find(jobs, fn j -> j.id == edge.target_job_id end)
    source_job = Enum.find(jobs, fn j -> j.id == edge.source_job_id end)
    source_job_name = hyphenate(source_job.name)
    target_job_name = hyphenate(target_job.name)

    %{
      name: "#{source_job_name}->#{target_job_name}",
      source_job: source_job_name
    }
    |> merge_edge_common_fields(edge, target_job)
  end

  defp merge_edge_common_fields(json, edge, target_job) do
    json
    |> Map.merge(%{
      target_job: hyphenate(target_job.name),
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

  defp pick_and_sort(map) do
    map
    |> Enum.filter(fn {key, _value} ->
      if Map.has_key?(map, :node_type) do
        @ordering_map[map.node_type]
        |> Enum.member?(key)
      else
        true
      end
    end)
    |> Enum.sort_by(
      fn {key, _value} ->
        if Map.has_key?(map, :node_type) do
          olist = @ordering_map[map.node_type]

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

      :condition_expression ->
        "condition_expression: #{v}"

      _ ->
        "#{yaml_safe_key(k)}: #{yaml_safe_string(v)}"
    end
  end

  defp yaml_safe_string(value) do
    # starts with alphanumeric
    # followed by alphanumeric or hyphen or underscore or @ or . or space
    # ends with alphanumeric
    if Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_\-@\. ]*[a-zA-Z0-9]$/, value) do
      value
    else
      ~s('#{value}')
    end
  end

  defp yaml_safe_key(key) do
    if key in @special_keys do
      key
    else
      key |> to_string() |> hyphenate() |> maybe_escape_key()
    end
  end

  defp maybe_escape_key(key) do
    # starts with alphanumeric
    # followed by alphanumeric or hyphen or underscore or @ or .
    # ends with alphanumeric
    if Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_\-@\.]*[a-zA-Z0-9]$/, key) do
      key
    else
      ~s("#{key}")
    end
  end

  defp handle_input(key, value, indentation) when is_binary(value) do
    "#{indentation}#{handle_binary(key, value, indentation)}"
  end

  defp handle_input(key, value, indentation) when is_number(value) do
    "#{indentation}#{yaml_safe_key(key)}: #{value}"
  end

  defp handle_input(key, value, indentation) when is_boolean(value) do
    "#{indentation}#{yaml_safe_key(key)}: #{value}"
  end

  defp handle_input(key, value, indentation) when value in [%{}, [], nil] do
    "#{indentation}#{yaml_safe_key(key)}: null"
  end

  defp handle_input(key, value, indentation) when is_map(value) do
    "#{indentation}#{yaml_safe_key(key)}:\n#{to_new_yaml(value, "#{indentation}  ")}"
  end

  defp handle_input(key, value, indentation) when is_list(value) do
    "#{indentation}#{yaml_safe_key(key)}:\n#{Enum.map_join(value, "\n", fn map -> "#{indentation}  #{yaml_safe_key(map.name)}:\n#{to_new_yaml(map, "#{indentation}    ")}" end)}"
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
        ytree = build_workflow_yaml_tree(workflow, project.project_credentials)
        Map.put(acc, hyphenate(workflow.name), ytree)
      end)

    credentials_map =
      project.project_credentials
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.reduce(%{}, fn project_credential, acc ->
        ytree = build_project_credential_yaml_tree(project_credential)

        Map.put(
          acc,
          project_credential_key(project_credential),
          ytree
        )
      end)

    %{
      name: project.name,
      description: project.description,
      node_type: :project,
      workflows: workflows_map,
      credentials: credentials_map
    }
  end

  defp project_credential_key(project_credential) do
    hyphenate(
      "#{project_credential.credential.user.email} #{project_credential.credential.name}"
    )
  end

  defp build_project_credential_yaml_tree(project_credential) do
    %{
      name: project_credential.credential.name,
      node_type: :credential,
      owner: project_credential.credential.user.email
    }
  end

  defp build_workflow_yaml_tree(workflow, project_credentials) do
    jobs =
      workflow.jobs
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn j -> job_to_treenode(j, project_credentials) end)

    triggers =
      workflow.triggers
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn t -> trigger_to_treenode(t) end)

    edges =
      workflow.edges
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn e ->
        edge_to_treenode(e, workflow.triggers, workflow.jobs)
      end)

    flow_map = %{jobs: jobs, edges: edges, triggers: triggers}

    flow_map
    |> to_workflow_yaml_tree(workflow)
  end

  @spec generate_new_yaml(Projects.Project.t(), [Snapshot.t()] | nil) ::
          {:ok, binary()}
  def generate_new_yaml(project, snapshots \\ nil)

  def generate_new_yaml(project, nil) do
    project =
      Lightning.Repo.preload(project, project_credentials: [credential: :user])

    yaml =
      project
      |> Workflows.get_workflows_for()
      |> build_yaml_tree(project)
      |> to_new_yaml()

    {:ok, yaml}
  end

  def generate_new_yaml(project, snapshots) when is_list(snapshots) do
    project =
      Lightning.Repo.preload(project, project_credentials: [credential: :user])

    yaml =
      snapshots
      |> Enum.sort_by(& &1.name)
      |> build_yaml_tree(project)
      |> to_new_yaml()

    {:ok, yaml}
  end
end
