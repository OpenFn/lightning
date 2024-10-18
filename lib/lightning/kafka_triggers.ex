defmodule Lightning.KafkaTriggers do
  @moduledoc """
  Contains the logic to manage kafka trigger and their associated pipelines.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Lightning.Accounts.UserNotifier
  alias Lightning.KafkaTriggers.MessageHandling
  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.Events

  def start_triggers do
    if supervisor = GenServer.whereis(:kafka_pipeline_supervisor) do
      find_enabled_triggers()
      |> Enum.each(fn trigger ->
        child_spec = generate_pipeline_child_spec(trigger)
        Supervisor.start_child(supervisor, child_spec)
      end)
    end

    :ok
  end

  def find_enabled_triggers do
    query =
      from t in Trigger,
        where: t.type == :kafka,
        where: t.enabled == true

    query |> Repo.all()
  end

  # Converts the initial_offset_reset_policy configuration value to a format
  # suitable for use by a `Pipeline` process.
  def initial_policy(%{initial_offset_reset_policy: initial_policy}) do
    cond do
      initial_policy in ["earliest", "latest"] ->
        initial_policy |> String.to_atom()

      String.match?(initial_policy, ~r/^\d+$/) ->
        {timestamp, _remainder} = Integer.parse(initial_policy)
        {:timestamp, timestamp}

      true ->
        :latest
    end
  end

  @doc """
  Generate the key that is used to identify duplicate messages when used in
  association with the trigger id.
  """
  def build_topic_partition_offset(%Broadway.Message{metadata: metadata}) do
    %{topic: topic, partition: partition, offset: offset} = metadata

    "#{topic}_#{partition}_#{offset}"
  end

  def enable_disable_triggers(triggers) do
    supervisor = GenServer.whereis(:kafka_pipeline_supervisor)

    triggers
    |> Enum.filter(&(&1.type == :kafka))
    |> Enum.each(fn
      %{enabled: true} = trigger ->
        spec = generate_pipeline_child_spec(trigger)
        Supervisor.start_child(supervisor, spec)

      %{enabled: false} = trigger ->
        Supervisor.terminate_child(supervisor, trigger.id)
        Supervisor.delete_child(supervisor, trigger.id)
    end)
  end

  @doc """
  Generate the child spec needed to start a `Pipeline` child process.
  """
  def generate_pipeline_child_spec(trigger) do
    %{
      connect_timeout: connect_timeout,
      group_id: group_id,
      hosts: hosts_list,
      password: password,
      sasl: sasl_type,
      ssl: ssl,
      topics: topics,
      username: username
    } = trigger.kafka_configuration

    hosts =
      hosts_list
      |> Enum.map(fn [host, port_string] ->
        {host, port_string |> String.to_integer()}
      end)

    sasl =
      if sasl_type do
        {sasl_type, username, password}
      else
        nil
      end

    offset_reset_policy = initial_policy(trigger.kafka_configuration)

    number_of_consumers = Lightning.Config.kafka_number_of_consumers()
    number_of_processors = Lightning.Config.kafka_number_of_processors()

    %{
      id: trigger.id,
      start: {
        Lightning.KafkaTriggers.Pipeline,
        :start_link,
        [
          [
            connect_timeout: connect_timeout * 1000,
            group_id: group_id,
            hosts: hosts,
            number_of_consumers: number_of_consumers,
            number_of_processors: number_of_processors,
            offset_reset_policy: offset_reset_policy,
            rate_limit: convert_rate_limit(),
            sasl: sasl,
            ssl: ssl,
            topics: topics,
            # sobelow_skip ["StringToAtom"]
            trigger_id: trigger.id |> String.to_atom()
          ]
        ]
      }
    }
  end

  def get_kafka_triggers_being_updated(changeset) do
    changeset
    |> Changeset.fetch_change(:triggers)
    |> case do
      :error ->
        []

      {:ok, triggers} ->
        triggers
    end
    |> Enum.filter(fn changeset ->
      {_data_or_change, type} =
        changeset
        |> Changeset.fetch_field(:type)

      type == :kafka
    end)
    |> Enum.map(fn changeset ->
      {_data_or_change, id} = Changeset.fetch_field(changeset, :id)
      id
    end)
  end

  def update_pipeline(supervisor, trigger_id) do
    Trigger
    |> Repo.get_by(id: trigger_id, type: :kafka)
    |> case do
      nil ->
        nil

      %{enabled: true} = trigger ->
        spec = generate_pipeline_child_spec(trigger)

        case Supervisor.start_child(supervisor, spec) do
          {:error, {:already_started, _pid}} ->
            Supervisor.terminate_child(supervisor, trigger.id)
            Supervisor.delete_child(supervisor, trigger.id)
            Supervisor.start_child(supervisor, spec)

          {:error, :already_present} ->
            Supervisor.delete_child(supervisor, trigger.id)
            Supervisor.start_child(supervisor, spec)

          response ->
            response
        end

      %{enabled: false} = trigger ->
        Supervisor.terminate_child(supervisor, trigger.id)
        Supervisor.delete_child(supervisor, trigger.id)
    end
  end

  def convert_rate_limit do
    per_second = Lightning.Config.kafka_number_of_messages_per_second()

    seconds_in_interval = 10

    messages_per_interval = (per_second * seconds_in_interval) |> trunc()

    %{interval: 10_000, messages_per_interval: messages_per_interval}
  end

  def notify_users_of_trigger_failure(trigger_id) do
    now = DateTime.utc_now()

    if send_notification?(now, last_notification_sent_at(trigger_id)) do
      notify_users(trigger_id, now)

      track_notification_sent(trigger_id, now)

      notify_any_other_nodes(trigger_id, now)
    end
  end

  defp last_notification_sent_at(trigger_id) do
    :persistent_term.get(failure_notification_tracking_key(trigger_id), nil)
  end

  def failure_notification_tracking_key(trigger_id) do
    {:kafka_trigger_failure_notification_sent_at, trigger_id}
  end

  defp notify_users(trigger_id, timestamp) do
    %{workflow: workflow} =
      Trigger
      |> Repo.get(trigger_id)
      |> Repo.preload(:workflow)

    workflow.project_id
    |> Projects.find_users_to_notify_of_trigger_failure()
    |> Enum.each(fn user ->
      UserNotifier.send_trigger_failure_mail(user, workflow, timestamp)
    end)
  end

  defp track_notification_sent(trigger_id, sent_at) do
    :persistent_term.put(
      failure_notification_tracking_key(trigger_id),
      sent_at
    )
  end

  defp notify_any_other_nodes(trigger_id, sent_at) do
    Events.kafka_trigger_notification_sent(trigger_id, sent_at)
  end

  def send_notification?(_sending_at, nil), do: true

  def send_notification?(sending_at, last_sent_at) do
    embargo_period =
      Lightning.Config.kafka_notification_embargo_seconds()

    DateTime.diff(sending_at, last_sent_at, :second) > embargo_period
  end

  def maybe_write_to_alternate_storage(trigger_id, %Broadway.Message{} = msg) do
    if Lightning.Config.kafka_alternate_storage_enabled?() do
      with {:ok, workflow_path} <- build_workflow_storage_path(trigger_id),
           :ok <- create_workflow_storage_directory(workflow_path),
           path <- build_file_path(workflow_path, trigger_id, msg),
           {:ok, data} <- encode_message(msg) do
        write_to_file(path, data)
      else
        error ->
          error
      end
    else
      :ok
    end
  end

  defp build_workflow_storage_path(trigger_id) do
    with base_path <- Lightning.Config.kafka_alternate_storage_file_path(),
         true <- base_path |> to_string() |> File.exists?(),
         %{workflow_id: workflow_id} <- Trigger |> Repo.get(trigger_id) do
      {:ok, Path.join(base_path, workflow_id)}
    else
      _anything ->
        {:error, :path_error}
    end
  end

  defp create_workflow_storage_directory(workflow_path) do
    case File.mkdir(workflow_path) do
      resp when resp == :ok or resp == {:error, :eexist} ->
        :ok

      _anything_else ->
        {:error, :workflow_dir_error}
    end
  end

  defp build_file_path(workflow_path, trigger_id, message) do
    workflow_path |> Path.join(alternate_storage_file_name(trigger_id, message))
  end

  def alternate_storage_file_name(trigger_id, message) do
    "#{trigger_id}_#{build_topic_partition_offset(message)}.json"
  end

  defp encode_message(message) do
    message
    |> Map.filter(fn {key, _val} -> key in [:data, :metadata] end)
    |> then(fn %{metadata: metadata} = message_export ->
      message_export
      |> Map.put(
        :metadata,
        MessageHandling.convert_headers_for_serialisation(metadata)
      )
    end)
    |> Jason.encode()
    |> case do
      {:error, _reason} ->
        {:error, :serialisation}

      ok_response ->
        ok_response
    end
  end

  defp write_to_file(path, data) do
    if File.write(path, data) == :ok do
      :ok
    else
      {:error, :writing}
    end
  end
end
