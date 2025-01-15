defmodule Lightning.KafkaTriggers.PipelineTest do
  use Lightning.DataCase

  import Mock
  import Mox
  import ExUnit.CaptureLog

  alias Ecto.Changeset
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Invocation
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageHandling
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.KafkaTriggers.Pipeline
  alias Lightning.Repo
  alias Lightning.WorkOrder
  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerNotificationSent

  describe ".start_link/1" do
    test "starts a Broadway GenServer process with SASL credentials" do
      connect_timeout = 15_000
      group_id = "my_group"
      hosts = [{"localhost", 9092}]
      number_of_consumers = 5
      number_of_processors = 11
      offset_reset_policy = :latest
      sasl = {:plain, "my_username", "my_secret"}
      sasl_expected = {:plain, "my_username", "my_secret"}
      ssl = true
      topics = ["my_topic"]
      trigger_id = :my_trigger_id

      rate_limit =
        %{interval: interval, messages_per_interval: allowed_messages} =
        KafkaTriggers.convert_rate_limit()

      with_mock Broadway,
        start_link: fn _module, _opts -> {:ok, "fake-pid"} end do
        Pipeline.start_link(
          connect_timeout: connect_timeout,
          group_id: group_id,
          hosts: hosts,
          number_of_consumers: number_of_consumers,
          number_of_processors: number_of_processors,
          offset_reset_policy: offset_reset_policy,
          rate_limit: rate_limit,
          sasl: sasl,
          ssl: ssl,
          topics: topics,
          trigger_id: trigger_id
        )

        assert called(
                 Broadway.start_link(
                   Pipeline,
                   name: trigger_id,
                   context: %{
                     trigger_id: trigger_id
                   },
                   producer: [
                     module: {
                       BroadwayKafka.Producer,
                       [
                         client_config: [
                           sasl: sasl_expected,
                           ssl: ssl,
                           connect_timeout: connect_timeout
                         ],
                         hosts: hosts,
                         group_id: group_id,
                         topics: topics,
                         offset_reset_policy: offset_reset_policy
                       ]
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
               )
      end
    end

    test "starts a Broadway GenServer process without SASL credentials" do
      connect_timeout = 15_000
      group_id = "my_group"
      hosts = [{"localhost", 9092}]
      number_of_consumers = 5
      number_of_processors = 11
      offset_reset_policy = :latest
      sasl = nil
      ssl = true
      topics = ["my_topic"]
      trigger_id = :my_trigger_id

      rate_limit =
        %{interval: interval, messages_per_interval: allowed_messages} =
        KafkaTriggers.convert_rate_limit()

      with_mock Broadway,
        start_link: fn _module, _opts -> {:ok, "fake-pid"} end do
        Pipeline.start_link(
          connect_timeout: connect_timeout,
          group_id: group_id,
          hosts: hosts,
          number_of_consumers: number_of_consumers,
          number_of_processors: number_of_processors,
          offset_reset_policy: offset_reset_policy,
          rate_limit: rate_limit,
          sasl: sasl,
          ssl: ssl,
          topics: topics,
          trigger_id: trigger_id
        )

        assert called(
                 Broadway.start_link(
                   Pipeline,
                   name: trigger_id,
                   context: %{
                     trigger_id: trigger_id
                   },
                   producer: [
                     module: {
                       BroadwayKafka.Producer,
                       [
                         client_config: [
                           ssl: ssl,
                           connect_timeout: connect_timeout
                         ],
                         hosts: hosts,
                         group_id: group_id,
                         topics: topics,
                         offset_reset_policy: offset_reset_policy
                       ]
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
               )
      end
    end
  end

  describe ".handle_message" do
    setup do
      trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 1),
          enabled: true
        )

      with_snapshot(trigger_1.workflow)

      trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 2, ssl: false),
          enabled: true
        )

      with_snapshot(trigger_2.workflow)

      context = %{trigger_id: trigger_1.id |> String.to_atom()}

      message = build_broadway_message()

      %{
        context: context,
        message: message,
        trigger_1: trigger_1,
        trigger_2: trigger_2
      }
    end

    test "returns the message", %{context: context, message: message} do
      assert Pipeline.handle_message(nil, message, context) == message
    end

    test "persists a WorkOrder", %{
      context: context,
      message: message,
      trigger_1: trigger
    } do
      Pipeline.handle_message(nil, message, context)

      assert %WorkOrder{dataclip: dataclip} =
               WorkOrder
               |> Repo.get_by(trigger_id: trigger.id)
               |> Repo.preload(dataclip: Invocation.Query.dataclip_with_body())

      assert dataclip.body["data"] == message.data |> Jason.decode!()
    end

    test "records the message for the purposes of future deduplication", %{
      context: context,
      message: message
    } do
      trigger_id = context.trigger_id |> Atom.to_string()

      Pipeline.handle_message(nil, message, context)

      message_record = Repo.one(TriggerKafkaMessageRecord)

      assert %TriggerKafkaMessageRecord{
               trigger_id: ^trigger_id,
               topic_partition_offset: "bar_topic_2_11"
             } = message_record
    end

    test "does not create WorkOrder if message is duplicate", %{
      context: context,
      message: message
    } do
      trigger_id = context.trigger_id |> Atom.to_string()

      insert_message_record(trigger_id)

      Pipeline.handle_message(nil, message, context)

      assert Repo.one(WorkOrder) == nil
    end

    test "marks message as failed when duplicate", %{
      context: context,
      message: message
    } do
      trigger_id = context.trigger_id |> Atom.to_string()

      insert_message_record(trigger_id)

      %{status: status} = Pipeline.handle_message(nil, message, context)

      assert {:failed, :duplicate} = status
    end

    test "marks message as failed for non-duplicate error", %{
      context: context,
      message: message
    } do
      persistence_error = {
        :error,
        %Changeset{changes: %{}, errors: [], valid?: false}
      }

      with_mock MessageHandling,
        persist_message: fn _multi, _trigger_id, _message ->
          persistence_error
        end do
        %{status: status} = Pipeline.handle_message(nil, message, context)

        assert {:failed, :persistence} = status
      end
    end

    test "marks message as failed for invalid json", %{context: context} do
      message = build_broadway_message(data_as_json: "invalid json", key: "")

      %{status: status} = Pipeline.handle_message(nil, message, context)

      assert {:failed, :invalid_data} = status
    end

    test "marks message as failed for json that is not an object", %{
      context: context
    } do
      message =
        build_broadway_message(
          data_as_json: "\"json but not an object\"",
          key: ""
        )

      %{status: status} = Pipeline.handle_message(nil, message, context)

      assert {:failed, :invalid_data} = status
    end

    test "marks messages as failed if work order creation is blocked", %{
      context: context,
      message: message,
      trigger_1: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      usage_context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^usage_context ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      %{status: status} = Pipeline.handle_message(nil, message, context)

      assert {:failed, :work_order_creation_blocked} = status
    end
  end

  describe ".handle_message - failure testing enabled" do
    setup do
      trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 1),
          enabled: true
        )

      trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 2, ssl: false),
          enabled: true
        )

      context = %{trigger_id: trigger_1.id |> String.to_atom()}

      message = build_broadway_message()

      :persistent_term.put({:kafka_trigger_test_failure, trigger_1.id}, true)

      %{
        context: context,
        message: message,
        trigger_1: trigger_1,
        trigger_2: trigger_2
      }
    end

    test "marks message as as a persistence failure", %{
      context: context,
      message: message
    } do
      %{status: status} = Pipeline.handle_message(nil, message, context)

      assert {:failed, :persistence} = status
    end

    test "does not persist a WorkOrder", %{
      context: context,
      message: message,
      trigger_1: trigger
    } do
      Pipeline.handle_message(nil, message, context)

      assert WorkOrder |> Repo.get_by(trigger_id: trigger.id) == nil
    end

    test "does not record the message", %{
      context: context,
      message: message
    } do
      Pipeline.handle_message(nil, message, context)

      assert Repo.one(TriggerKafkaMessageRecord) == nil
    end

    test "indicates that the test was completed", %{
      context: context,
      message: message,
      trigger_1: trigger
    } do
      Pipeline.handle_message(nil, message, context)

      refute :persistent_term.get({:kafka_trigger_test_failure, trigger.id})
    end
  end

  describe ".handle_failed/2" do
    setup do
      messages = [
        build_broadway_message(offset: 1) |> Broadway.Message.failed(:duplicate),
        build_broadway_message(offset: 2) |> Broadway.Message.failed(:who_knows)
      ]

      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: build(:triggers_kafka_configuration)
        )

      %{
        context: %{trigger_id: trigger.id |> String.to_atom()},
        messages: messages
      }
    end

    test "returns the messages unmodified", %{
      context: context,
      messages: messages
    } do
      assert Pipeline.handle_failed(messages, context) == messages
    end

    test "creates a log entry for a failed message", %{
      context: context,
      messages: messages
    } do
      [message_1, message_2] = messages

      expected_entry_1 = message_1 |> expected_duplicate_log_message(context)
      expected_entry_2 = message_2 |> expected_general_error_message(context)

      fun = fn -> Pipeline.handle_failed(messages, context) end

      assert capture_log(fun) =~ expected_entry_1
      assert capture_log(fun) =~ expected_entry_2
    end

    test "notifies Sentry for failures that are not related to duplication", %{
      context: context,
      messages: messages
    } do
      [message_1, message_2] = messages

      notification = "Kafka pipeline - message processing error"

      extra_1 = message_1 |> expected_extra_sentry_data(context)
      extra_2 = message_2 |> expected_extra_sentry_data(context)

      with_mock Sentry,
        capture_message: fn _data, _extra -> :ok end do
        Pipeline.handle_failed(messages, context)

        assert_not_called(Sentry.capture_message(notification, extra: extra_1))
        assert_called(Sentry.capture_message(notification, extra: extra_2))
      end
    end

    test "notifies the project admin of a persistence failure", %{
      context: context,
      messages: [message_1, message_2]
    } do
      trigger_id = context.trigger_id |> Atom.to_string()

      persistence_failure_message =
        build_broadway_message(offset: 3)
        |> Broadway.Message.failed(:persistence)

      messages = [
        message_1,
        persistence_failure_message,
        message_2
      ]

      Events.subscribe_to_kafka_trigger_updated()

      Pipeline.handle_failed(messages, context)

      assert_receive %KafkaTriggerNotificationSent{trigger_id: ^trigger_id}
    end

    defp expected_duplicate_log_message(message, context) do
      "Kafka Pipeline Duplicate Message:" <>
        " Trigger_id `#{context.trigger_id}`" <>
        " Topic `#{message.metadata.topic}`" <>
        " Partition `#{message.metadata.partition}`" <>
        " Offset `#{message.metadata.offset}`"
    end

    defp expected_general_error_message(message, context) do
      %{status: {:failed, type}} = message

      "Kafka Pipeline Error:" <>
        " Type `#{type}`" <>
        " Trigger_id `#{context.trigger_id}`" <>
        " Topic `#{message.metadata.topic}`" <>
        " Partition `#{message.metadata.partition}`" <>
        " Offset `#{message.metadata.offset}`" <>
        " Key `#{message.metadata.key}`"
    end

    defp expected_extra_sentry_data(message, context) do
      %{status: {:failed, type}} = message

      %{
        key: message.metadata.key,
        offset: message.metadata.offset,
        partition: message.metadata.partition,
        topic: message.metadata.topic,
        trigger_id: context.trigger_id,
        type: type
      }
    end
  end

  describe ".handle_failed/2 - storing persistence failures" do
    setup %{tmp_dir: tmp_dir} = context do
      stub(Lightning.MockConfig, :kafka_alternate_storage_enabled?, fn ->
        true
      end)

      stub(Lightning.MockConfig, :kafka_alternate_storage_file_path, fn ->
        tmp_dir
      end)

      persistence_failure_message_1 =
        build_broadway_message(offset: 3)
        |> Broadway.Message.failed(:persistence)

      persistence_failure_message_2 =
        build_broadway_message(offset: 4)
        |> Broadway.Message.failed(:persistence)

      messages = [
        build_broadway_message(offset: 1) |> Broadway.Message.failed(:duplicate),
        persistence_failure_message_1,
        build_broadway_message(offset: 2) |> Broadway.Message.failed(:who_knows),
        persistence_failure_message_2
      ]

      %{id: trigger_id, workflow_id: workflow_id} =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: build(:triggers_kafka_configuration)
        )

      path = Path.join(tmp_dir, workflow_id)

      if Map.get(context, :write_error, false) do
        path
        |> tap(&File.mkdir!(&1))
        |> tap(&File.chmod!(&1, 0o000))
      end

      %{
        context: %{trigger_id: trigger_id |> String.to_atom()},
        messages: messages,
        path: path,
        persistence_failure_message_1: persistence_failure_message_1,
        persistence_failure_message_2: persistence_failure_message_2
      }
    end

    @tag :tmp_dir
    test "dumps persistence_failed messages to alternate storage if enabled", %{
      context: context,
      messages: messages,
      path: path,
      persistence_failure_message_1: persistence_failure_message_1,
      persistence_failure_message_2: persistence_failure_message_2
    } do
      Pipeline.handle_failed(messages, context)

      file_name_1 =
        context.trigger_id
        |> KafkaTriggers.alternate_storage_file_name(
          persistence_failure_message_1
        )

      file_name_2 =
        context.trigger_id
        |> KafkaTriggers.alternate_storage_file_name(
          persistence_failure_message_2
        )

      files = File.ls!(path)

      assert files |> Enum.count() == 2
      assert file_name_1 in files
      assert file_name_2 in files
    end

    @tag tmp_dir: true, write_error: true
    test "writes to log if there is an error writing to alternate storage", %{
      context: context,
      messages: messages,
      persistence_failure_message_1: persistence_failure_message_1,
      persistence_failure_message_2: persistence_failure_message_2
    } do
      expected_entry_1 =
        persistence_failure_message_1
        |> expected_alternate_storage_error_message(context)

      expected_entry_2 =
        persistence_failure_message_2
        |> expected_alternate_storage_error_message(context)

      fun = fn -> Pipeline.handle_failed(messages, context) end

      assert capture_log(fun) =~ expected_entry_1
      assert capture_log(fun) =~ expected_entry_2
    end

    @tag tmp_dir: true, write_error: true
    test "notifies Sentry if there is an error writing to alternate storage", %{
      context: context,
      messages: messages,
      persistence_failure_message_1: persistence_failure_message_1,
      persistence_failure_message_2: persistence_failure_message_2
    } do
      extra_1 =
        persistence_failure_message_1
        |> expected_alternate_storage_sentry_data(context)

      extra_2 =
        persistence_failure_message_2
        |> expected_alternate_storage_sentry_data(context)

      notification = "Kafka pipeline - alternate storage failed: writing"

      with_mock Sentry,
        capture_message: fn _data, _extra -> :ok end do
        Pipeline.handle_failed(messages, context)

        assert_called(Sentry.capture_message(notification, extra: extra_1))
        assert_called(Sentry.capture_message(notification, extra: extra_2))
      end
    end

    defp expected_alternate_storage_error_message(message, context) do
      "Kafka Pipeline Error:" <>
        " Type `alternate_storage_failed: writing`" <>
        " Trigger_id `#{context.trigger_id}`" <>
        " Topic `#{message.metadata.topic}`" <>
        " Partition `#{message.metadata.partition}`" <>
        " Offset `#{message.metadata.offset}`" <>
        " Key `#{message.metadata.key}`"
    end

    defp expected_alternate_storage_sentry_data(message, context) do
      %{
        key: message.metadata.key,
        offset: message.metadata.offset,
        partition: message.metadata.partition,
        topic: message.metadata.topic,
        trigger_id: context.trigger_id |> Atom.to_string()
      }
    end
  end

  describe "maybe_notify_users/2" do
    setup do
      Events.subscribe_to_kafka_trigger_updated()

      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: build(:triggers_kafka_configuration)
        )

      %{
        trigger_id: trigger.id
      }
    end

    test "does not notify the user if there are no persistence failures", %{
      trigger_id: trigger_id
    } do
      messages = [
        build_broadway_message() |> Broadway.Message.failed(:other),
        build_broadway_message() |> Broadway.Message.failed(:other)
      ]

      Pipeline.maybe_notify_users(messages, trigger_id)

      refute_receive %KafkaTriggerNotificationSent{}
    end

    test "notifies users if there is a message with a persistence failure", %{
      trigger_id: trigger_id
    } do
      messages = [
        build_broadway_message() |> Broadway.Message.failed(:other),
        build_broadway_message() |> Broadway.Message.failed(:persistence),
        build_broadway_message() |> Broadway.Message.failed(:other)
      ]

      Pipeline.maybe_notify_users(messages, trigger_id)

      assert_receive %KafkaTriggerNotificationSent{trigger_id: ^trigger_id}
    end

    test "notifies users if there are multiple persistence failures", %{
      trigger_id: trigger_id
    } do
      messages = [
        build_broadway_message() |> Broadway.Message.failed(:other),
        build_broadway_message() |> Broadway.Message.failed(:persistence),
        build_broadway_message() |> Broadway.Message.failed(:other),
        build_broadway_message() |> Broadway.Message.failed(:persistence),
        build_broadway_message() |> Broadway.Message.failed(:other)
      ]

      Pipeline.maybe_notify_users(messages, trigger_id)

      assert_receive %KafkaTriggerNotificationSent{trigger_id: ^trigger_id}
    end
  end

  defp build_broadway_message(opts \\ []) do
    data =
      Keyword.get(
        opts,
        :data_as_json,
        %{interesting: "stuff"} |> Jason.encode!()
      )

    key = Keyword.get(opts, :key, "abc_123_def")
    offset = Keyword.get(opts, :offset, 11)

    %Broadway.Message{
      data: data,
      metadata: %{
        offset: offset,
        partition: 2,
        key: key,
        headers: [],
        ts: 1_715_164_718_283,
        topic: "bar_topic"
      },
      acknowledger: nil,
      batcher: :default,
      batch_key: {"bar_topic", 2},
      batch_mode: :bulk,
      status: :ok
    }
  end

  defp configuration(opts) do
    index = opts |> Keyword.get(:index)
    sasl = opts |> Keyword.get(:sasl, true)
    ssl = opts |> Keyword.get(:ssl, true)

    password = if sasl, do: "secret-#{index}", else: nil
    sasl_type = if sasl, do: :plain, else: nil
    username = if sasl, do: "my-user-#{index}", else: nil

    %{
      group_id: "lightning-#{index}",
      hosts: [["host-#{index}", "9092"], ["other-host-#{index}", "9093"]],
      hosts_string: "host-#{index}:9092, other-host-#{index}:9093",
      initial_offset_reset_policy: "earliest",
      password: password,
      sasl: sasl_type,
      ssl: ssl,
      topics: ["topic-#{index}-1", "topic-#{index}-2"],
      topics_string: "topic-#{index}-1, topic-#{index}-2",
      username: username
    }
  end

  defp insert_message_record(trigger_id) do
    TriggerKafkaMessageRecord.changeset(
      %TriggerKafkaMessageRecord{},
      %{
        topic_partition_offset: "bar_topic_2_11",
        trigger_id: trigger_id
      }
    )
    |> Repo.insert()
  end
end
