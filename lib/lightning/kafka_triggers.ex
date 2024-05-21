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
      "partition_timestamps" => partition_timestamps
    } = existing_kafka_configuration

    updated_partition_timestamps =
      partition_timestamps
      |> case do
        existing = %{^partition_key => existing_timestamp} when existing_timestamp < timestamp ->
          existing |> Map.merge(%{partition_key => timestamp})
        existing = %{^partition_key => _existing_timestamp} ->
          existing
        existing ->
          existing |> Map.merge(%{partition_key => timestamp})
      end

    updated_kafka_configuration =
      existing_kafka_configuration
      |> Map.merge(%{"partition_timestamps" => updated_partition_timestamps})

    trigger
    |> Trigger.changeset(%{kafka_configuration: updated_kafka_configuration})
    |> Repo.update()
  end

  def determine_offset_reset_policy(trigger) do
    %Trigger{kafka_configuration: kafka_configuration} = trigger

    case kafka_configuration do
      config = %{"partition_timestamps" => ts} when map_size(ts) == 0 ->
        initial_policy(config)
      %{"partition_timestamps" => ts} ->
        earliest_timestamp(ts)
    end
  end

  defp initial_policy(%{"initial_offset_reset_policy" => initial_policy}) do
    case initial_policy do
      policy when is_integer(policy) -> {:timestamp, policy}
      policy when policy in ["earliest", "latest"] -> policy |> String.to_atom()
      _unrecognised_policy -> :latest
    end
  end

  defp earliest_timestamp(timestamps) do
    timestamp = timestamps |> Map.values() |> Enum.sort |> hd()

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

    %{
      "group_id" => group_id,
      "hosts" => hosts,
      "initial_offset_reset_policy" => policy,
      "partition_timestamps" => %{},
      "sasl" => convert_sasl_option(sasl_option),
      "ssl" => ssl,
      "topics" => topics
    }
  end

  defp convert_sasl_option([mechanism, username, password]) do
    ["#{mechanism}", username, password]
  end
  defp convert_sasl_option(nil), do: nil

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

  def send_after(pid, message, delay) do
    Process.send_after(pid, message, delay)
  end

  def process_candidate_for(candidate_set) do
    candidate = find_candidate_for(candidate_set)

    %{data: data, trigger: %{workflow: workflow} = trigger} = candidate

    {:ok, %WorkOrder{id: work_order_id}} =
      WorkOrders.create_for(trigger,
        workflow: workflow,
        dataclip: %{
          body: data |> Jason.decode!(),
          type: :kafka,
          project_id: workflow.project_id
        },
        without_run: false
      ) |> IO.inspect()

    candidate
    |> TriggerKafkaMessage.changeset(%{work_order_id: work_order_id})
    |> Repo.update()

    :ok
  end

  def find_candidate_for(%{trigger_id: trigger_id, topic: topic, key: key}) do
    query = from t in TriggerKafkaMessage,
      where: t.trigger_id == ^trigger_id and t.topic == ^topic and t.key == ^key,
      order_by: t.message_timestamp,
      limit: 1,
      preload: [trigger: [:workflow]]

    query |> Repo.one()
  end
end
