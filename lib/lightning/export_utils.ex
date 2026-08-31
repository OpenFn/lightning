defmodule Lightning.ExportUtils do
  @moduledoc """
  Module that expose a function generating a complete and valid yaml string
  from a project and its workflows.
  """

  alias Lightning.ExportUtils.DuplicateKeyError
  alias Lightning.ExportUtils.Scalar
  alias Lightning.Projects
  alias Lightning.Workflows
  alias Lightning.Workflows.Snapshot

  @kafka_trigger_fields [
    :hosts,
    :topics,
    :initial_offset_reset_policy,
    :connect_timeout
  ]

  @webhook_response_config_fields [:success_code, :error_code]

  @ordering_map %{
    project: [
      :name,
      :description,
      :collections,
      :channels,
      :credentials,
      :globals,
      :workflows
    ],
    collection: [:name],
    channel: [:name, :destination_url, :enabled, :destination_credential],
    credential: [:name, :owner],
    workflow: [:name, :jobs, :triggers, :edges],
    job: [:name, :adaptor, :credential, :globals, :body],
    trigger: [
      :type,
      :webhook_reply,
      :webhook_response_config,
      :cron_expression,
      :cron_cursor_job,
      :enabled,
      :kafka_configuration
    ],
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

  # Two entities whose names hyphenate to the same key would silently overwrite
  # one another in the spec, and the CLI addresses them by that key. Refuse,
  # and name both so whoever hit it knows which two to rename.
  defp put_identity_key!(acc, key, tree, kind) do
    case Map.fetch(acc, key) do
      {:ok, %{name: existing}} ->
        raise DuplicateKeyError,
          kind: kind,
          key: key,
          first: existing,
          second: tree.name

      :error ->
        Map.put(acc, key, tree)
    end
  end

  # Sorted so that a project with more than one collision always reports the
  # same one first.
  defp ensure_unique_job_keys!(jobs, workflow_name) do
    jobs
    |> Enum.group_by(&hyphenate(&1.name))
    |> Enum.sort_by(fn {key, _jobs} -> key end)
    |> Enum.each(fn
      {_key, [_only]} ->
        :ok

      {key, [first, second | _rest]} ->
        raise DuplicateKeyError,
          kind: "jobs in #{workflow_name}",
          key: key,
          first: first.name,
          second: second.name
    end)
  end

  # An edge key is a label. Nothing parses it, and the edge body carries its own
  # identity in source_job, source_trigger and target_job. That matters because
  # the key is built by joining two job keys with `->`, and a job may legally
  # hold a `>`: jobs named `a` and `b->c` produce the same key as `a->b` and
  # `c`. So a collision here is disambiguated rather than refused.
  #
  # The suffix is checked against both the original keys and the ones already
  # handed out, so it cannot collide with a name further down the list.
  defp disambiguate_edge_keys(edges) do
    taken = MapSet.new(edges, & &1.name)

    edges
    |> Enum.map_reduce(MapSet.new(), fn edge, used ->
      name = free_edge_name(edge.name, taken, used)
      {%{edge | name: name}, MapSet.put(used, name)}
    end)
    |> elem(0)
  end

  defp free_edge_name(name, taken, used) do
    if MapSet.member?(used, name) do
      next_free_edge_name(name, 2, taken, used)
    else
      name
    end
  end

  defp next_free_edge_name(name, suffix, taken, used) do
    candidate = "#{name}-#{suffix}"

    if MapSet.member?(taken, candidate) or MapSet.member?(used, candidate) do
      next_free_edge_name(name, suffix + 1, taken, used)
    else
      candidate
    end
  end

  defp job_to_treenode(job, project_credentials) do
    project_credential =
      Enum.find(project_credentials, fn pc ->
        pc.id == job.project_credential_id
      end)

    %{
      # The identifier here for our YAML reducer will be the hyphenated name
      id: job_key(job),
      name: job.name,
      node_type: :job,
      adaptor: job.adaptor,
      body: job.body,
      credential:
        project_credential && project_credential_key(project_credential)
    }
  end

  defp trigger_to_treenode(trigger, jobs) do
    base = %{
      id: trigger.id,
      enabled: trigger.enabled,
      name: Atom.to_string(trigger.type),
      node_type: :trigger,
      type: Atom.to_string(trigger.type)
    }

    case trigger.type do
      :cron ->
        base
        |> Map.put(:cron_expression, trigger.cron_expression)
        |> then(fn cron ->
          if trigger.cron_cursor_job_id do
            cursor_job =
              Enum.find(jobs, fn j -> j.id == trigger.cron_cursor_job_id end)

            Map.put(cron, :cron_cursor_job, cursor_job && job_key(cursor_job))
          else
            cron
          end
        end)

      :kafka ->
        kafka_config =
          trigger.kafka_configuration
          |> Map.take(@kafka_trigger_fields)
          |> Enum.map(fn
            {:hosts, hosts} when is_list(hosts) ->
              {:hosts,
               Enum.map(hosts, fn host_port -> Enum.join(host_port, ":") end)}

            other ->
              other
          end)
          |> Enum.sort_by(
            fn {key, _val} ->
              Enum.find_index(@kafka_trigger_fields, &(&1 == key))
            end,
            :asc
          )

        Map.put(base, :kafka_configuration, kafka_config)

      :webhook ->
        base
        |> maybe_put_webhook_reply(trigger.webhook_reply)
        |> maybe_put_webhook_response_config(trigger.webhook_response_config)
    end
  end

  defp maybe_put_webhook_reply(map, nil), do: map

  defp maybe_put_webhook_reply(map, reply) when is_atom(reply) do
    Map.put(map, :webhook_reply, Atom.to_string(reply))
  end

  defp maybe_put_webhook_response_config(map, %{} = config) do
    webhook_response =
      Map.reject(
        %{
          success_code: config.success_code,
          error_code: config.error_code
        },
        fn {_k, v} -> is_nil(v) end
      )
      |> Enum.sort_by(
        fn {key, _val} ->
          Enum.find_index(@webhook_response_config_fields, &(&1 == key))
        end,
        :asc
      )

    if length(webhook_response) > 0 do
      Map.put(map, :webhook_response_config, webhook_response)
    else
      map
    end
  end

  defp maybe_put_webhook_response_config(map, _), do: map

  defp edge_to_treenode(%{source_job_id: nil} = edge, triggers, jobs) do
    source_trigger =
      Enum.find(triggers, fn t -> t.id == edge.source_trigger_id end)

    target_job = Enum.find(jobs, fn j -> j.id == edge.target_job_id end)
    trigger_name = to_string(source_trigger.type)
    target_job_name = job_key(target_job)

    %{
      name: "#{trigger_name}->#{target_job_name}",
      source_trigger: trigger_name
    }
    |> merge_edge_common_fields(edge, target_job)
  end

  defp edge_to_treenode(%{source_trigger_id: nil} = edge, _triggers, jobs) do
    target_job = Enum.find(jobs, fn j -> j.id == edge.target_job_id end)
    source_job = Enum.find(jobs, fn j -> j.id == edge.source_job_id end)
    source_job_name = job_key(source_job)
    target_job_name = job_key(target_job)

    %{
      name: "#{source_job_name}->#{target_job_name}",
      source_job: source_job_name
    }
    |> merge_edge_common_fields(edge, target_job)
  end

  defp merge_edge_common_fields(json, edge, target_job) do
    json
    |> Map.merge(%{
      target_job: job_key(target_job),
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

  # :adaptor and :cron_expression used to be hard-coded as "#{k}: '#{v}'", the
  # one place left in this module that concatenated a value into the spec
  # without escaping it. They go through Scalar now, but through the forced
  # quote rather than the general one: a cron with no wildcard in it, such as
  # `5 4 1 1 1`, is bare-legal, and emitting it bare would be a diff in every
  # synced project repo that has one. Same output as before, escaped now.
  defp handle_binary(k, v, i) do
    case k do
      k when k in [:body, :description, :condition_expression] ->
        "#{yaml_safe_key(k)}: #{Scalar.encode_block(v, i)}"

      k when k in [:adaptor, :cron_expression] ->
        "#{yaml_safe_key(k)}: #{Scalar.encode_quoted_value(v)}"

      _ ->
        "#{yaml_safe_key(k)}: #{yaml_safe_string(v)}"
    end
  end

  defp yaml_safe_string(value), do: Scalar.encode_value(value)

  defp yaml_safe_key(key) do
    if key in @special_keys do
      key
    else
      key |> to_string() |> hyphenate() |> Scalar.encode_key()
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
    yaml_value =
      if Keyword.keyword?(value) do
        to_new_yaml(value, "#{indentation}  ")
      else
        handle_list_value(value, indentation)
      end

    "#{indentation}#{yaml_safe_key(key)}:\n#{yaml_value}"
  end

  defp handle_list_value(value, indentation) do
    Enum.map_join(value, "\n", fn
      map when is_map(map) ->
        "#{indentation}  #{yaml_safe_key(map.name)}:\n#{to_new_yaml(map, "#{indentation}    ")}"

      val when is_binary(val) ->
        "#{indentation}  - #{yaml_safe_string(val)}"

      val ->
        "#{indentation}  - #{val}"
    end)
  end

  defp to_new_yaml(map, indentation \\ "")

  defp to_new_yaml(map, indentation) when is_map(map) do
    map
    |> pick_and_sort()
    |> to_new_yaml(indentation)
  end

  defp to_new_yaml(keyword, indentation) do
    keyword
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
        put_identity_key!(acc, hyphenate(workflow.name), ytree, "workflows")
      end)

    credentials_map =
      project.project_credentials
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.reduce(%{}, fn project_credential, acc ->
        ytree = build_project_credential_yaml_tree(project_credential)

        put_identity_key!(
          acc,
          project_credential_key(project_credential),
          ytree,
          "credentials"
        )
      end)

    collections_map =
      project.collections
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.reduce(%{}, fn collection, acc ->
        ytree = build_collection_yaml_tree(collection)

        put_identity_key!(acc, hyphenate(collection.name), ytree, "collections")
      end)

    channels_map =
      project.channels
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.reduce(%{}, fn channel, acc ->
        ytree = build_channel_yaml_tree(channel, project.project_credentials)

        put_identity_key!(acc, hyphenate(channel.name), ytree, "channels")
      end)

    %{
      name: project.name,
      description: project.description,
      node_type: :project,
      workflows: workflows_map,
      credentials: credentials_map,
      collections: collections_map,
      channels: channels_map
    }
  end

  defp job_key(job) do
    hyphenate(job.name)
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

  defp build_collection_yaml_tree(collection) do
    %{
      name: collection.name,
      node_type: :collection
    }
  end

  defp build_channel_yaml_tree(channel, project_credentials) do
    project_credential_id = channel_destination_project_credential_id(channel)

    project_credential =
      project_credential_id &&
        Enum.find(project_credentials, fn pc ->
          pc.id == project_credential_id
        end)

    %{
      name: channel.name,
      destination_url: channel.destination_url,
      enabled: channel.enabled,
      node_type: :channel,
      destination_credential:
        project_credential && project_credential_key(project_credential)
    }
  end

  defp channel_destination_project_credential_id(%{destination_auth_method: nil}),
    do: nil

  defp channel_destination_project_credential_id(%{
         destination_auth_method: %{project_credential_id: id}
       }),
       do: id

  defp channel_destination_project_credential_id(_), do: nil

  defp build_workflow_yaml_tree(workflow, project_credentials) do
    jobs =
      workflow.jobs
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn j -> job_to_treenode(j, project_credentials) end)

    ensure_unique_job_keys!(jobs, workflow.name)

    triggers =
      workflow.triggers
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn t -> trigger_to_treenode(t, workflow.jobs) end)

    edges =
      workflow.edges
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(fn e ->
        edge_to_treenode(e, workflow.triggers, workflow.jobs)
      end)
      |> disambiguate_edge_keys()

    flow_map = %{jobs: jobs, edges: edges, triggers: triggers}

    flow_map
    |> to_workflow_yaml_tree(workflow)
  end

  @doc """
  Builds the project spec.

  Returns `{:error, message}` when two entities in the project would be written
  under the same spec key. That is refused rather than exported, because the
  key is what the CLI addresses the entity by and the export used to drop one
  of the pair without saying anything. The message names both so the user can
  go and rename one.
  """
  @spec generate_new_yaml(Projects.Project.t(), [Snapshot.t()] | nil) ::
          {:ok, binary()} | {:error, binary()}
  def generate_new_yaml(project, snapshots \\ nil)

  def generate_new_yaml(project, nil) do
    project = preload_for_export(project)

    with_duplicate_key_error(fn ->
      project
      |> Workflows.get_workflows_for()
      |> build_yaml_tree(project)
      |> to_new_yaml()
    end)
  end

  def generate_new_yaml(project, snapshots) when is_list(snapshots) do
    project = preload_for_export(project)

    with_duplicate_key_error(fn ->
      snapshots
      |> Enum.sort_by(& &1.name)
      |> build_yaml_tree(project)
      |> to_new_yaml()
    end)
  end

  defp preload_for_export(project) do
    Lightning.Repo.preload(project,
      project_credentials: [credential: :user],
      collections: [],
      channels: [destination_auth_method: :project_credential]
    )
  end

  # build_yaml_tree/2 raises from several levels down, so the alternative to
  # rescuing here is threading an error tuple through every builder. One rescue
  # at the single public boundary is the smaller change.
  defp with_duplicate_key_error(build) do
    {:ok, build.()}
  rescue
    error in DuplicateKeyError -> {:error, Exception.message(error)}
  end
end
