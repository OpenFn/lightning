defmodule Lightning.KafkaTriggers.Pipeline do
  @moduledoc """
  Broadway pipeline that processes messages from Kafka clusters and persists
  the received messages if they are not duplicating a previous message.
  """
  use Broadway

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageHandling
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord

  require Logger

  def start_link(opts) do
    number_of_consumers = opts |> Keyword.get(:number_of_consumers)
    number_of_processors = opts |> Keyword.get(:number_of_processors)
    trigger_id = opts |> Keyword.get(:trigger_id)

    %{interval: interval, messages_per_interval: allowed_messages} =
      opts
      |> Keyword.get(:rate_limit)

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
        concurrency: number_of_consumers,
        rate_limiting: [
          allowed_messages: allowed_messages,
          interval: interval
        ]
      ],
      processors: [
        default: [
          concurrency: number_of_processors
        ]
      ],
      batchers: []
    )
  end

  @impl true
  def handle_message(_processor, message, context) do
    trigger_id = context.trigger_id |> Atom.to_string()

    if simulate_failure?(trigger_id) do
      simulate_failure(trigger_id, message)
    else
      process_message(trigger_id, message)
    end
  end

  defp simulate_failure?(trigger_id) do
    :persistent_term.get({:kafka_trigger_test_failure, trigger_id}, nil)
  end

  defp simulate_failure(trigger_id, message) do
    :persistent_term.put({:kafka_trigger_test_failure, trigger_id}, false)

    Broadway.Message.failed(message, :persistence)
  end

  # Dialyzer does not correctly match the types that can be returned by
  # MessageHandling.persist_message/3. The {:ok, _} match fails.
  @dialyzer {:no_match, process_message: 2}
  defp process_message(trigger_id, message) do
    Multi.new()
    |> track_message(trigger_id, message)
    |> MessageHandling.persist_message(trigger_id, message)
    |> case do
      {:ok, _} ->
        message

      {
        :error,
        %{
          errors: [
            trigger_id: {
              "has already been taken",
              [
                constraint: :unique,
                constraint_name: "trigger_kafka_message_records_pkey"
              ]
            }
          ]
        }
      } ->
        Broadway.Message.failed(message, :duplicate)

      {:error, %Changeset{}} ->
        Broadway.Message.failed(message, :persistence)

      {:error, :data_is_not_json} ->
        Broadway.Message.failed(message, :invalid_data)

      {:error, :data_is_not_json_object} ->
        Broadway.Message.failed(message, :invalid_data)

      {:error, :work_order_creation_blocked, _reason} ->
        Broadway.Message.failed(message, :work_order_creation_blocked)
    end
  end

  defp track_message(multi, trigger_id, message) do
    topic_partition_offset =
      KafkaTriggers.build_topic_partition_offset(message)

    record_changeset =
      TriggerKafkaMessageRecord.changeset(
        %TriggerKafkaMessageRecord{},
        %{
          topic_partition_offset: topic_partition_offset,
          trigger_id: trigger_id
        }
      )

    multi |> Multi.insert(:record, record_changeset)
  end

  @impl true
  def handle_failed(messages, context) do
    trigger_id = context.trigger_id |> Atom.to_string()

    messages
    |> Enum.each(fn message ->
      create_log_entry(message, context)
      notify_sentry(message, context)
    end)

    maybe_write_to_alternate_storage(messages, trigger_id)

    maybe_notify_users(messages, trigger_id)

    messages
  end

  defp create_log_entry(%{status: {:failed, :duplicate}} = message, context) do
    %{
      metadata: %{
        offset: offset,
        partition: partition,
        topic: topic
      }
    } = message

    log_entry =
      "Kafka Pipeline Duplicate Message:" <>
        " Trigger_id `#{context.trigger_id}`" <>
        " Topic `#{topic}`" <>
        " Partition `#{partition}`" <>
        " Offset `#{offset}`"

    Logger.warning(log_entry)
  end

  defp create_log_entry(%{status: {:failed, type}} = message, context) do
    %{
      metadata: %{
        key: key,
        offset: offset,
        partition: partition,
        topic: topic
      }
    } = message

    log_message =
      "Kafka Pipeline Error:" <>
        " Type `#{type}`" <>
        " Trigger_id `#{context.trigger_id}`" <>
        " Topic `#{topic}`" <>
        " Partition `#{partition}`" <>
        " Offset `#{offset}`" <>
        " Key `#{key}`"

    Logger.error(log_message)
  end

  defp notify_sentry(%{status: {:failed, :duplicate}}, _context), do: nil

  defp notify_sentry(%{status: {:failed, type}} = message, context) do
    %{
      metadata: %{
        key: key,
        offset: offset,
        partition: partition,
        topic: topic
      }
    } = message

    Sentry.capture_message(
      "Kafka pipeline - message processing error",
      extra: %{
        key: key,
        offset: offset,
        partition: partition,
        topic: topic,
        trigger_id: context.trigger_id,
        type: type
      }
    )
  end

  defp notify_sentry(message, context, error_message) do
    %{
      metadata: %{
        key: key,
        offset: offset,
        partition: partition,
        topic: topic
      }
    } = message

    Sentry.capture_message(
      error_message,
      extra: %{
        key: key,
        offset: offset,
        partition: partition,
        topic: topic,
        trigger_id: context.trigger_id
      }
    )
  end

  defp maybe_write_to_alternate_storage(messages, trigger_id) do
    messages
    |> Enum.filter(&(&1.status == {:failed, :persistence}))
    |> Enum.each(fn message ->
      write_to_alternate_storage(message, trigger_id)
    end)
  end

  defp write_to_alternate_storage(message, trigger_id) do
    trigger_id
    |> KafkaTriggers.maybe_write_to_alternate_storage(message)
    |> case do
      :ok ->
        nil

      {:error, reason} ->
        handle_alternate_storage_failure(message, trigger_id, reason)
    end
  end

  defp handle_alternate_storage_failure(message, trigger_id, reason) do
    create_alternate_storage_log_entry(message, trigger_id, reason)

    notify_sentry(
      message,
      %{trigger_id: trigger_id},
      "Kafka pipeline - alternate storage failed: #{reason}"
    )
  end

  defp create_alternate_storage_log_entry(message, trigger_id, reason) do
    %{
      metadata: %{
        key: key,
        offset: offset,
        partition: partition,
        topic: topic
      }
    } = message

    log_message =
      "Kafka Pipeline Error:" <>
        " Type `alternate_storage_failed: #{reason}`" <>
        " Trigger_id `#{trigger_id}`" <>
        " Topic `#{topic}`" <>
        " Partition `#{partition}`" <>
        " Offset `#{offset}`" <>
        " Key `#{key}`"

    Logger.error(log_message)
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

    base_config = [{:ssl, ssl}, {:connect_timeout, connect_timeout}]

    case sasl do
      nil ->
        base_config

      sasl ->
        [{:sasl, sasl} | base_config]
    end
  end

  def maybe_notify_users(messages, trigger_id) do
    if messages |> Enum.any?(&(&1.status == {:failed, :persistence})) do
      KafkaTriggers.notify_users_of_trigger_failure(trigger_id)
    end
  end
end
