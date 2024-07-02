defmodule Lightning.KafkaTriggers.Pipeline do
  use Broadway

  # import Ecto.Query

  alias Ecto.Multi
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Repo
  # alias Lightning.Workflows.Trigger

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
        partition: _partition,
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


    Multi.new()
    |> Multi.insert(:record, record_changeset)
    |> Multi.insert(:message, message_changeset)
    |> Repo.transaction()
    # case record_changeset |> Repo.insert() do
    #   # TODO Use transaction for DB operations
    #   {:ok, _} ->
    #     trigger =
    #       Trigger
    #       |> preload([:workflow])
    #       |> Repo.get(trigger_id |> Atom.to_string())
    #
    #     %TriggerKafkaMessage{}
    #     |> TriggerKafkaMessage.changeset(%{
    #       data: data,
    #       key: key,
    #       message_timestamp: timestamp,
    #       metadata: message.metadata,
    #       offset: offset,
    #       topic: topic,
    #       trigger_id: trigger_id |> Atom.to_string()
    #     })
    #     |> Repo.insert!()
    #
    #     trigger
    #     |> KafkaTriggers.update_partition_data(partition, timestamp)
    #
    #   {:error,
    #    %{errors: [trigger_id: {_, [constraint: :unique, constraint_name: _]}]}} ->
    #     IO.puts(
    #       "**** #{trigger_id} received DUPLICATE on #{partition} produced at #{timestamp}"
    #     )
    #
    #   _ ->
    #     raise "Unhandled error when persisting TriggerKafkaMessageRecord"
    # end

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
