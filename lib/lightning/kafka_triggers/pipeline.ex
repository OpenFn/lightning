defmodule Lightning.KafkaTriggers.Pipeline do
  use Broadway

  require Logger

  alias Ecto.Multi
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Repo
  alias Lightning.Workflows.Trigger

  def start_link(opts) do
    trigger_id = opts |> Keyword.get(:trigger_id)

    Broadway.start_link(__MODULE__,
      name: trigger_id,
      context: %{
        trigger_id: trigger_id
      },
      producer: [
        module: {
          BroadwayKafka.Producer,
          build_producer_opts(opts)
        },
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: 10
        ]
      ],
      batchers: []
    )
  end

  def handle_message(_processor, message, context) do
    %{trigger_id: trigger_id} = context

    %{
      data: data,
      metadata: %{
        key: key,
        offset: offset,
        partition: partition,
        topic: topic,
        ts: timestamp
      }
    } = message

    topic_partition_offset =
      KafkaTriggers.build_topic_partition_offset(message)

    record_changeset =
      TriggerKafkaMessageRecord.changeset(
        %TriggerKafkaMessageRecord{},
        %{
          topic_partition_offset: topic_partition_offset,
          trigger_id: trigger_id |> Atom.to_string()
        }
      )

    message_changeset =
      %TriggerKafkaMessage{}
      |> TriggerKafkaMessage.changeset(%{
        data: data,
        key: key,
        message_timestamp: timestamp,
        metadata: message.metadata,
        offset: offset,
        topic: topic,
        trigger_id: trigger_id |> Atom.to_string()
      })

    trigger_changeset =
      Trigger
      |> Repo.get(trigger_id |> Atom.to_string())
      |> KafkaTriggers.update_partition_data(partition, timestamp)

    Multi.new()
    |> Multi.insert(:record, record_changeset)
    |> Multi.insert(:message, message_changeset)
    |> Multi.update(:trigger, trigger_changeset)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        nil

      {
        :error,
        :record,
        %{errors: [trigger_id: {"has already been taken", _constraints}]},
        _changes_so_far
      } ->
        log_message =
          "Kafka Pipeline Duplicate Message:" <>
            " Trigger_id: `#{trigger_id}`" <>
            " Topic: `#{topic}`" <>
            " Partition: `#{partition}`" <>
            " Offset: `#{offset}`"

        Logger.warning(log_message)

      {:error, _step, _error_changes, _changes_so_far} ->
        Sentry.capture_message(
          "Kafka pipeline - message processing error",
          extra: %{
            key: key,
            offset: offset,
            partition: partition,
            topic: topic,
            trigger_id: trigger_id
          }
        )

        log_message =
          "Kafka Pipeline Error:" <>
            " Trigger_id: `#{context.trigger_id}`" <>
            " Topic: `#{message.metadata.topic}`" <>
            " Partition: `#{message.metadata.partition}`" <>
            " Offset: `#{message.metadata.offset}`" <>
            " Key: `#{message.metadata.key}`"

        Logger.error(log_message)
    end

    message
  end

  defp build_producer_opts(opts) do
    hosts = opts |> Keyword.get(:hosts)
    group_id = opts |> Keyword.get(:group_id)
    offset_reset_policy = opts |> Keyword.get(:offset_reset_policy)
    topics = opts |> Keyword.get(:topics)

    [
      client_config: client_config(opts),
      hosts: hosts,
      group_id: group_id,
      topics: topics,
      offset_reset_policy: offset_reset_policy
    ]
  end

  defp client_config(opts) do
    connect_timeout = opts |> Keyword.get(:connect_timeout)
    sasl = opts |> Keyword.get(:sasl)
    ssl = opts |> Keyword.get(:ssl)

    # TODO Not tested
    base_config = [{:ssl, ssl}, {:connect_timeout, connect_timeout}]

    case sasl do
      nil ->
        base_config

      sasl ->
        [{:sasl, sasl} | base_config]
    end
  end
end
