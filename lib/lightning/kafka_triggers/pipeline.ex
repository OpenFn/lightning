defmodule Lightning.KafkaTriggers.Pipeline do
  use Broadway

  import Ecto.Query

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

    case record_changeset |> Repo.insert() do
      # TODO Use transaction for DB operations
      {:ok, _} ->
        trigger =
          Trigger
          |> preload([:workflow])
          |> Repo.get(trigger_id |> Atom.to_string())

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
        |> Repo.insert!()

        trigger
        |> KafkaTriggers.update_partition_data(partition, timestamp)

        # IO.inspect(message, label: :full_message)
        # %Broadway.Message{data: data, metadata: %{ts: ts}} = message

        IO.puts(
          ">>>> #{trigger_id} received #{data} on #{partition} produced at #{timestamp}"
        )

      # IO.inspect(message)
      {:error,
       %{errors: [trigger_id: {_, [constraint: :unique, constraint_name: _]}]}} ->
        IO.puts(
          "**** #{trigger_id} received DUPLICATE #{data} on #{partition} produced at #{timestamp}"
        )

      _ ->
        raise "Unhandled error when persisting TriggerKafkaMessageRecord"
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
    sasl = opts |> Keyword.get(:sasl)
    ssl = opts |> Keyword.get(:ssl)

    base_config = [{:ssl, ssl}]

    case sasl do
      nil ->
        base_config

      sasl ->
        {mechanism, username, password} = sasl
        [{:sasl, {String.to_atom(mechanism), username, password}} | base_config]
    end
  end
end
