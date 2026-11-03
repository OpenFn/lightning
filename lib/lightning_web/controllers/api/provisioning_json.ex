defmodule LightningWeb.API.ProvisioningJSON do
  @moduledoc false

  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelAuthMethod
  alias Lightning.Collections.Collection
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkflowVersions

  def render("create.json", %{project: project, conn: _conn}) do
    %{"data" => as_json(project)}
  end

  def as_json(%Project{} = project) do
    Ecto.embedded_dump(project, :json)
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
    |> Map.put(
      :channels,
      project.channels
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
        ~w(id name inserted_at updated_at deleted_at lock_version concurrency)a
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

    if module == Workflow do
      version_history = WorkflowVersions.history_for(workflow_or_snapshot)
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

    webhook_response_config =
      trigger.webhook_response_config &&
        Map.take(trigger.webhook_response_config, [
          :success_code,
          :error_code
        ])
        |> drop_keys_with_nil_value()

    trigger
    |> Map.take(~w(id type custom_path cron_expression enabled webhook_reply
         cron_cursor_job_id)a)
    |> drop_unusable_custom_path()
    |> Map.put(:webhook_response_config, webhook_response_config)
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

  def as_json(%Channel{} = channel) do
    %{
      id: channel.id,
      name: channel.name,
      destination_url: channel.destination_url,
      enabled: channel.enabled,
      destination_credential_id: destination_credential_id(channel)
    }
  end

  defp destination_credential_id(%Channel{destination_auth_method: method}) do
    case method do
      %ChannelAuthMethod{project_credential_id: id} -> id
      _ -> nil
    end
  end

  defp drop_keys_with_nil_value(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end

  # A path written before the naming rules would fail validation when this
  # document is deployed into another project and take the whole run with it,
  # the same guard `ExportUtils` and `MergeProjects` apply.
  defp drop_unusable_custom_path(%{custom_path: path} = trigger)
       when is_binary(path) do
    if Lightning.Workflows.Trigger.valid_custom_path?(path) do
      trigger
    else
      Map.delete(trigger, :custom_path)
    end
  end

  defp drop_unusable_custom_path(trigger), do: trigger
end
