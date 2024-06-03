defmodule Lightning.KafkaTriggers do
  import Ecto.Query

  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.Repo
  alias Lightning.Workflows.Trigger
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders

  def find_enabled_triggers do
    query =
      from t in Trigger,
        where: t.type == :kafka,
        where: t.enabled == true

    query |> Repo.all()
  end

  def update_partition_data(trigger, partition, timestamp) do
    partition_key = partition |> Integer.to_string()

    %Trigger{
      kafka_configuration: existing_kafka_configuration
    } = trigger

    %{
      partition_timestamps: partition_timestamps
    } = existing_kafka_configuration

    updated_partition_timestamps =
      partition_timestamps
      |> case do
        existing = %{^partition_key => existing_timestamp}
        when existing_timestamp < timestamp ->
          existing |> Map.merge(%{partition_key => timestamp})

        existing = %{^partition_key => _existing_timestamp} ->
          existing

        existing ->
          existing |> Map.merge(%{partition_key => timestamp})
      end

    updated_kafka_configuration = %{
      partition_timestamps: updated_partition_timestamps
    }

    trigger
    |> Trigger.changeset(%{kafka_configuration: updated_kafka_configuration})
    |> Repo.update()
  end

  def determine_offset_reset_policy(trigger) do
    %Trigger{kafka_configuration: kafka_configuration} = trigger

    case kafka_configuration do
      config = %{partition_timestamps: ts} when map_size(ts) == 0 ->
        initial_policy(config)

      %{partition_timestamps: ts} ->
        earliest_timestamp(ts)
    end
  end

  defp initial_policy(%{initial_offset_reset_policy: initial_policy}) do
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

  defp earliest_timestamp(timestamps) do
    timestamp = timestamps |> Map.values() |> Enum.sort() |> hd()

    {:timestamp, timestamp}
  end

  def build_trigger_configuration(opts \\ []) do
    group_id = opts |> Keyword.fetch!(:group_id)
    hosts = opts |> Keyword.fetch!(:hosts)
    policy_option = opts |> Keyword.fetch!(:initial_offset_reset_policy)
    topics = opts |> Keyword.fetch!(:topics)
    sasl_option = opts |> Keyword.get(:sasl, nil)
    ssl = opts |> Keyword.get(:ssl, false)

    policy = policy_config_value(policy_option)

    [sasl_type, username, password] = case sasl_option do
      nil ->
        [nil, nil, nil]
      [sasl_type, username, password] ->
        ["#{sasl_type}", username, password]
    end

    %{
      group_id: group_id,
      hosts: hosts,
      initial_offset_reset_policy: policy,
      partition_timestamps: %{},
      password: password,
      sasl: sasl_type,
      ssl: ssl,
      topics: topics,
      username: username
    }
  end

  defp policy_config_value(initial_policy) do
    case initial_policy do
      policy when is_integer(policy) ->
        policy

      policy when policy in [:earliest, :latest] ->
        "#{policy}"

      _unrecognised_policy ->
        raise "initial_offset_reset_policy must be :earliest, :latest or integer"
    end
  end

  def build_topic_partition_offset(%Broadway.Message{metadata: metadata}) do
    %{topic: topic, partition: partition, offset: offset} = metadata

    "#{topic}_#{partition}_#{offset}"
  end

  def find_message_candidate_sets do
    query =
      from t in TriggerKafkaMessage,
        select: [t.trigger_id, t.topic, t.key],
        distinct: [t.trigger_id, t.topic, t.key]

    query
    |> Repo.all()
    |> Enum.map(fn [trigger_id, topic, key] ->
      %{trigger_id: trigger_id, topic: topic, key: key}
    end)
  end

  def process_candidate_for(candidate_set) do
    Repo.transaction(fn ->
      candidate_set
      |> find_candidate_for()
      |> lock("FOR UPDATE SKIP LOCKED")
      |> Repo.one()
      |> case do
        nil ->
          nil

        candidate ->
          handle_candidate(candidate)
      end
    end)

    :ok
  end

  defp handle_candidate(%{work_order: nil} = candidate) do
    %{
      data: data,
      metadata: metadata,
      trigger: %{workflow: workflow} = trigger
    } = candidate

    {:ok, %WorkOrder{id: work_order_id}} =
      WorkOrders.create_for(trigger,
        workflow: workflow,
        dataclip: %{
          body: data |> Jason.decode!(),
          request: metadata,
          type: :kafka,
          project_id: workflow.project_id
        },
        without_run: false
      )

    candidate
    |> TriggerKafkaMessage.changeset(%{work_order_id: work_order_id})
    |> Repo.update!()
  end

  defp handle_candidate(%{work_order: work_order} = candidate) do
    if successful?(work_order), do: candidate |> Repo.delete()
  end

  def find_candidate_for(%{trigger_id: trigger_id, topic: topic, key: nil}) do
    from t in TriggerKafkaMessage,
      where: t.trigger_id == ^trigger_id and t.topic == ^topic and is_nil(t.key),
      order_by: t.offset,
      limit: 1,
      preload: [:work_order, trigger: [:workflow]]
  end

  def find_candidate_for(%{trigger_id: trigger_id, topic: topic, key: key}) do
    from t in TriggerKafkaMessage,
      where: t.trigger_id == ^trigger_id and t.topic == ^topic and t.key == ^key,
      order_by: t.offset,
      limit: 1,
      preload: [:work_order, trigger: [:workflow]]
  end

  def successful?(%{state: state}) do
    state == :success
  end

  def enable_disable_triggers(triggers) do
    supervisor = GenServer.whereis(:kafka_pipeline_supervisor)

    triggers
    |> Enum.filter(& &1.type == :kafka)
    |> Enum.each(fn
      %{enabled: true} = trigger ->
        spec = generate_pipeline_child_spec(trigger)
        Supervisor.start_child(supervisor, spec)
      %{enabled: false} = trigger ->
        Supervisor.terminate_child(supervisor, trigger.id)
        Supervisor.delete_child(supervisor, trigger.id)
    end)
  end

  def generate_pipeline_child_spec(trigger) do
    %{
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

    sasl = if sasl_type do
      {sasl_type, username, password}
    else
      nil
    end

    offset_reset_policy = determine_offset_reset_policy(trigger)

    %{
      id: trigger.id,
      start: {
        Lightning.KafkaTriggers.Pipeline,
        :start_link,
        [
          [
            group_id: group_id,
            hosts: hosts,
            offset_reset_policy: offset_reset_policy,
            trigger_id: trigger.id |> String.to_atom(),
            sasl: sasl,
            ssl: ssl,
            topics: topics
          ]
        ]
      }
    }
  end
end
