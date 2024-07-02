defmodule Lightning.KafkaTriggersTest do
  use Lightning.DataCase, async: false

  import Mock

  require Lightning.Run

  alias Ecto.Changeset
  alias Lightning.Invocation
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.Run
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  describe ".start_triggers/0" do
    setup do
      {:ok, pid} = start_supervised(PipelineSupervisor)

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

      %{pid: pid, trigger_1: trigger_1, trigger_2: trigger_2}
    end

    test "does not attempt anything if the supervisor is not running" do
      stop_supervised!(PipelineSupervisor)

      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 1} end do
        KafkaTriggers.start_triggers()

        assert_not_called(Supervisor.count_children(:_))
        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "returns :ok if the supervisor is not running" do
      stop_supervised!(PipelineSupervisor)

      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 1} end do
        assert KafkaTriggers.start_triggers() == :ok
      end
    end

    test "returns :ok if supervisor already has chidren" do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 1} end do
        assert KafkaTriggers.start_triggers() == :ok
      end
    end

    test "asks supervisor to start a child for each trigger", %{
      pid: pid,
      trigger_1: trigger_1,
      trigger_2: trigger_2
    } do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 0} end do
        KafkaTriggers.start_triggers()

        assert_called(
          Supervisor.start_child(pid, child_spec(trigger: trigger_1, index: 1))
        )

        assert_called(
          Supervisor.start_child(
            pid,
            child_spec(trigger: trigger_2, index: 2, ssl: false)
          )
        )
      end
    end

    test "handles the case where the consumer group does not use SASL", %{
      pid: pid
    } do
      no_auth_trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 3, sasl: false),
          enabled: true
        )

      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 0} end do
        KafkaTriggers.start_triggers()

        assert_called(
          Supervisor.start_child(
            pid,
            child_spec(trigger: no_auth_trigger, index: 3, sasl: false)
          )
        )
      end
    end

    test "returns :ok" do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 0} end do
        assert KafkaTriggers.start_triggers() == :ok
      end
    end
  end

  describe ".find_enabled_triggers/0" do
    test "returns enabled kafka triggers" do
      trigger_1 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)

      trigger_2 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)

      not_kafka_trigger =
        insert(:trigger, type: :cron, enabled: true)

      not_enabled =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: false)

      triggers = KafkaTriggers.find_enabled_triggers()

      assert triggers |> contains?(trigger_1)
      assert triggers |> contains?(trigger_2)
      refute triggers |> contains?(not_kafka_trigger)
      refute triggers |> contains?(not_enabled)
    end

    defp contains?(triggers, %Trigger{id: id}) do
      triggers
      |> Enum.any?(&(&1.id == id))
    end
  end

  describe ".update_partition_data" do
    setup do
      %{partition: 7, timestamp: 124}
    end

    test "adds data for partition if the trigger has no partition data", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(partition_timestamps: %{})
        )

      changeset = 
        trigger
        |> KafkaTriggers.update_partition_data(partition, timestamp)

      assert %Changeset{data: ^trigger, changes: changes} = changeset

      assert changes == %{
        kafka_configuration: %{
          partition_timestamps: %{"#{partition}" => timestamp}
        }
      }
      # trigger
      # |> assert_persisted_config(%{"#{partition}" => timestamp})
    end

    test "adds data for partition if partition is new but there is data", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(partition_timestamps: %{"3" => 123})
        )

      changeset =
        trigger
        |> KafkaTriggers.update_partition_data(partition, timestamp)

      assert %Changeset{data: ^trigger, changes: changes} = changeset

      assert changes == %{
        kafka_configuration: %{
          partition_timestamps: %{
            "3" => 123,
            "#{partition}" => timestamp
          }
        }
      }
      # trigger
      # |> assert_persisted_config(%{
      #   "3" => 123,
      #   "#{partition}" => timestamp
      # })
    end

    test "does not update partition data if persisted timestamp is newer", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration:
            configuration(
              partition_timestamps: %{
                "3" => 123,
                "#{partition}" => timestamp + 1
              }
            )
        )

      changeset =
        trigger
        |> KafkaTriggers.update_partition_data(partition, timestamp)

      assert %Changeset{data: ^trigger, changes: changes} = changeset

      assert changes == %{
        kafka_configuration: %{
          partition_timestamps: %{
            "3" => 123,
            "#{partition}" => timestamp + 1
          }
        }
      }
      #
      # trigger
      # |> assert_persisted_config(%{
      #   "3" => 123,
      #   "#{partition}" => timestamp + 1
      # })
    end

    test "updates persisted partition data if persisted timestamp is older", %{
      partition: partition,
      timestamp: timestamp
    } do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration:
            configuration(
              partition_timestamps: %{
                "3" => 123,
                "#{partition}" => timestamp - 1
              }
            )
        )

      expected_timestamps = %{
        "3" => 123,
        "#{partition}" => timestamp
      }

      changeset =
        trigger
        |> KafkaTriggers.update_partition_data(partition, timestamp)

      assert %Changeset{data: ^trigger, changes: changes} = changeset

      assert %{
        kafka_configuration: %{
          changes: %{partition_timestamps: ^expected_timestamps}
        }
      } = changes

      # assert changes == %{
      #   kafka_configuration: %Changeset{
      #     changes: %{
      #       partition_timestamps: %{
      #         "3" => 123,
      #         "#{partition}" => timestamp
      #       }
      #     }
      #   }
      # }
      # trigger
      # |> KafkaTriggers.update_partition_data(partition, timestamp)
      #
      # trigger
      # |> assert_persisted_config(%{
      #   "3" => 123,
      #   "#{partition}" => timestamp
      # })
    end

    # defp assert_persisted_config(trigger, expected_partition_timestamps) do
    #   reloaded_trigger = Trigger |> Repo.get(trigger.id)
    #
    #   %Trigger{
    #     kafka_configuration: %{
    #       partition_timestamps: partition_timestamps
    #     }
    #   } = reloaded_trigger
    #
    #   assert partition_timestamps == expected_partition_timestamps
    # end
  end

  describe ".determine_offset_reset_policy" do
    test "returns :earliest if 'earliest'" do
      policy =
        "earliest"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :earliest
    end

    test "returns :latest if 'latest'" do
      policy =
        "latest"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :latest
    end

    test "returns policy if timestamp as a string" do
      timestamp = "1715312900123"

      policy =
        timestamp
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == {:timestamp, timestamp |> String.to_integer()}
    end

    test "returns :latest if unrecognised string" do
      policy =
        "woteva"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :latest
    end

    test "returns earliest partition timestamp if data is available" do
      partition_timestamps = %{
        "1" => 1_715_312_900_121,
        "2" => 1_715_312_900_120,
        "3" => 1_715_312_900_123
      }

      policy =
        "earliest"
        |> build_trigger(partition_timestamps)
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == {:timestamp, 1_715_312_900_120}
    end

    defp build_trigger(initial_offset_reset, partition_timestamps \\ %{}) do
      # TODO Centralise the generation of config to avoid drift
      kafka_configuration = %{
        group_id: "lightning-1",
        hosts: [["host-1", 9092], ["other-host-1", 9093]],
        initial_offset_reset_policy: initial_offset_reset,
        partition_timestamps: partition_timestamps,
        sasl: nil,
        ssl: false,
        topics: ["bar_topic"]
      }

      build(:trigger, type: :kafka, kafka_configuration: kafka_configuration)
    end
  end

  describe "build_trigger_configuration" do
    setup do
      %{
        group_id: "my_little_group",
        hosts: [["host-1", 9092], ["host-2", 9092]],
        initial_offset_reset_policy: 1_715_764_260_123,
        topics: ["my_little_topic"]
      }
    end

    test "returns Kafka trigger configurtion with some defaults", %{
      group_id: group_id,
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      expected = %{
        group_id: group_id,
        hosts: hosts,
        initial_offset_reset_policy: initial_offset_reset_policy,
        partition_timestamps: %{},
        password: nil,
        sasl: nil,
        ssl: false,
        topics: topics,
        username: nil
      }

      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy,
          topics: topics
        )

      assert config == expected
    end

    test "allows sasl and ssl to be set", %{
      group_id: group_id,
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      sasl = [:plain, "my_user", "my_secret"]
      ssl = true

      expected = %{
        group_id: group_id,
        hosts: hosts,
        initial_offset_reset_policy: initial_offset_reset_policy,
        partition_timestamps: %{},
        password: "my_secret",
        sasl: "plain",
        ssl: true,
        topics: topics,
        username: "my_user"
      }

      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy,
          sasl: sasl,
          ssl: ssl,
          topics: topics
        )

      assert config == expected
    end

    test "converts an initial_offset_reset_policy of :earliest", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: :earliest,
          topics: topics
        )

      assert %{initial_offset_reset_policy: "earliest"} = config
    end

    test "converts an initial_offset_reset_policy of :latest", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      config =
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: :latest,
          topics: topics
        )

      assert %{initial_offset_reset_policy: "latest"} = config
    end

    test "raises on an unrecognised initial_offset_reset_policy", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      assert_raise RuntimeError, ~r/initial_offset_reset_policy/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: :unobtainium,
          topics: topics
        )
      end
    end

    test "raises an error if group_id is not provided", %{
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      assert_raise KeyError, ~r/group_id/, fn ->
        KafkaTriggers.build_trigger_configuration(
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy,
          topics: topics
        )
      end
    end

    test "raises an error if hosts is not provided", %{
      group_id: group_id,
      initial_offset_reset_policy: initial_offset_reset_policy,
      topics: topics
    } do
      assert_raise KeyError, ~r/hosts/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          initial_offset_reset_policy: initial_offset_reset_policy,
          topics: topics
        )
      end
    end

    test "raises an error if initial_offset_reset_policy is not provided", %{
      group_id: group_id,
      hosts: hosts,
      topics: topics
    } do
      assert_raise KeyError, ~r/initial_offset_reset_policy/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          topics: topics
        )
      end
    end

    test "raises an error if topics is not provided", %{
      group_id: group_id,
      hosts: hosts,
      initial_offset_reset_policy: initial_offset_reset_policy
    } do
      assert_raise KeyError, ~r/topics/, fn ->
        KafkaTriggers.build_trigger_configuration(
          group_id: group_id,
          hosts: hosts,
          initial_offset_reset_policy: initial_offset_reset_policy
        )
      end
    end
  end

  describe ".build_topic_partition_offset" do
    test "builds based on the proivded message" do
      message = build_broadway_message("foo", 2, 1)
      assert KafkaTriggers.build_topic_partition_offset(message) == "foo_2_1"

      message = build_broadway_message("bar", 4, 2)
      assert KafkaTriggers.build_topic_partition_offset(message) == "bar_4_2"
    end

    defp build_broadway_message(topic, partition, offset) do
      %Broadway.Message{
        data: %{interesting: "stuff"} |> Jason.encode!(),
        metadata: %{
          offset: offset,
          partition: partition,
          key: "",
          headers: [],
          ts: 1_715_164_718_283,
          topic: topic
        },
        acknowledger: nil,
        batcher: :default,
        batch_key: {"bar_topic", 2},
        batch_mode: :bulk,
        status: :ok
      }
    end
  end

  describe ".find_message_candidate_sets" do
    test "returns all distinct combinations of trigger, topic, key" do
      trigger_1 = insert(:trigger, type: :kafka)
      trigger_2 = insert(:trigger, type: :kafka)

      message =
        insert(
          :trigger_kafka_message,
          trigger: trigger_1,
          topic: "topic-1",
          key: "key-1"
        )

      _message_duplicate =
        insert(
          :trigger_kafka_message,
          trigger: trigger_1,
          topic: "topic-1",
          key: "key-1"
        )

      different_key =
        insert(
          :trigger_kafka_message,
          trigger: trigger_1,
          topic: "topic-1",
          key: "key-2"
        )

      nil_key =
        insert(
          :trigger_kafka_message,
          trigger: trigger_1,
          topic: "topic-1",
          key: nil
        )

      different_topic =
        insert(
          :trigger_kafka_message,
          trigger: trigger_1,
          topic: "topic-2",
          key: "key-1"
        )

      different_trigger =
        insert(
          :trigger_kafka_message,
          trigger: trigger_2,
          topic: "topic-1",
          key: "key-1"
        )

      sets = KafkaTriggers.find_message_candidate_sets()

      assert sets |> Enum.count() == 5

      assert [%{trigger_id: _, topic: _, key: _} | _other] = sets

      assert sets |> number_of_sets_for(message) == 1
      assert sets |> number_of_sets_for(different_key) == 1
      assert sets |> number_of_sets_for(nil_key) == 1
      assert sets |> number_of_sets_for(different_topic) == 1
      assert sets |> number_of_sets_for(different_trigger) == 1
    end

    def number_of_sets_for(sets, %{trigger: trigger, topic: topic, key: key}) do
      sets
      |> Enum.count(fn
        %{trigger_id: _} = set ->
          set.trigger_id == trigger.id && set.topic == topic && set.key == key

        _ ->
          false
      end)
    end
  end

  describe ".process_candidate_for/1" do
    setup do
      trigger = insert(:trigger, type: :kafka)

      other_message =
        insert(
          :trigger_kafka_message,
          key: "other-key",
          offset: 1,
          topic: "other-test-topic",
          work_order: nil
        )

      message_1 =
        insert(
          :trigger_kafka_message,
          data: %{triggers: :test} |> Jason.encode!(),
          key: "test-key",
          metadata: %{
            offset: 1,
            partition: 1,
            topic: "test-topic"
          },
          offset: 1,
          processing_data: %{"existing" => "data"},
          topic: "test-topic",
          trigger: trigger,
          work_order: nil
        )

      message_2 =
        insert(
          :trigger_kafka_message,
          data: %{triggers: :more_test} |> Jason.encode!(),
          key: "test-key",
          offset: 2,
          topic: "test-topic",
          trigger: trigger,
          work_order: nil
        )

      candidate_set = %{
        trigger_id: message_1.trigger.id,
        topic: message_1.topic,
        key: message_1.key
      }

      %{
        candidate_set: candidate_set,
        message_1: message_1,
        message_2: message_2,
        other_message: other_message
      }
    end

    test "returns :ok but does nothing if there is no candidate for the set", %{
      candidate_set: candidate_set
    } do
      no_such_set = candidate_set |> Map.merge(%{key: "no-such-key"})

      assert KafkaTriggers.process_candidate_for(no_such_set) == :ok
    end

    test "if candidate exists sans work_order, creates work_order", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      %{trigger: %{workflow: workflow} = trigger} = message_1
      project_id = workflow.project_id

      assert KafkaTriggers.process_candidate_for(candidate_set) == :ok

      %{work_order: work_order} =
        TriggerKafkaMessage
        |> Repo.get(message_1.id)
        |> Repo.preload(
          work_order: [
            [dataclip: Invocation.Query.dataclip_with_body()],
            :runs,
            trigger: [workflow: [:project]],
            workflow: [:project]
          ]
        )

      expected_body = %{
        "data" => %{
          "triggers" => "test"
        },
        "request" => %{
          "offset" => 1,
          "partition" => 1,
          "topic" => "test-topic"
        }
      }

      assert %WorkOrder{
               dataclip: %{
                 body: ^expected_body,
                 project_id: ^project_id,
                 type: :kafka
               },
               trigger: ^trigger,
               workflow: ^workflow
             } = work_order
    end

    test "candidate, no workorder, broken data adds an error message", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      message_1
      |> TriggerKafkaMessage.changeset(%{data: "not a JSON object"})
      |> Repo.update!()

      expected =
        message_1.processing_data
        |> Map.merge(%{"errors" => ["Data is not a JSON object"]})

      assert KafkaTriggers.process_candidate_for(candidate_set) == :ok

      %{work_order_id: nil, processing_data: processing_data} =
        TriggerKafkaMessage
        |> Repo.get(message_1.id)

      assert processing_data == expected
    end

    test "if candidate has successful work_order, deletes candidate", %{
      candidate_set: candidate_set,
      message_1: message_1,
      message_2: message_2,
      other_message: other_message
    } do
      KafkaTriggers.process_candidate_for(candidate_set)

      updated_message_1 =
        TriggerKafkaMessage
        |> Repo.get(message_1.id)
        |> Repo.preload(:work_order)

      %{work_order: work_order} = updated_message_1

      work_order
      |> WorkOrder.changeset(%{state: :success})
      |> Repo.update()

      assert KafkaTriggers.process_candidate_for(candidate_set) == :ok

      assert TriggerKafkaMessage |> Repo.get(message_1.id) == nil
      assert TriggerKafkaMessage |> Repo.get(message_2.id) != nil
      assert TriggerKafkaMessage |> Repo.get(other_message.id) != nil
    end

    test "if candidate does not have successful work_order, does not delete", %{
      candidate_set: candidate_set,
      message_1: message_1,
      message_2: message_2,
      other_message: other_message
    } do
      assert KafkaTriggers.process_candidate_for(candidate_set) == :ok

      assert KafkaTriggers.process_candidate_for(candidate_set) == :ok

      assert TriggerKafkaMessage |> Repo.get(message_1.id) != nil
      assert TriggerKafkaMessage |> Repo.get(message_2.id) != nil
      assert TriggerKafkaMessage |> Repo.get(other_message.id) != nil
    end

    test "rolls back if an error occurs", %{
      candidate_set: candidate_set
    } do
      with_mock(
        TriggerKafkaMessage,
        [:passthrough],
        changeset: fn _message, _changes -> raise "rollback" end
      ) do
        assert_raise RuntimeError, ~r/rollback/, fn ->
          KafkaTriggers.process_candidate_for(candidate_set)
        end
      end

      assert WorkOrder |> Repo.all() == []
    end
  end

  describe "find_candidate_for/1" do
    setup do
      other_trigger = insert(:trigger)
      trigger = insert(:trigger)

      _other_trigger_set_message_1 =
        insert(
          :trigger_kafka_message,
          key: "set_key",
          message_timestamp: 10 |> timestamp_from_offset,
          offset: 1,
          topic: "set_topic",
          trigger: other_trigger
        )

      _other_key_set_message_1 =
        insert(
          :trigger_kafka_message,
          key: "other_set_key",
          message_timestamp: 10 |> timestamp_from_offset,
          offset: 1,
          topic: "set_topic",
          trigger: trigger
        )

      _other_key_set_message_1 =
        insert(
          :trigger_kafka_message,
          key: "set_key",
          message_timestamp: 10 |> timestamp_from_offset,
          offset: 1,
          topic: "other_set_topic",
          trigger: trigger
        )

      _set_message_2 =
        insert(
          :trigger_kafka_message,
          key: "set_key",
          message_timestamp: 20 |> timestamp_from_offset,
          offset: 102,
          topic: "set_topic",
          trigger: trigger
        )

      _set_message_3 =
        insert(
          :trigger_kafka_message,
          key: "set_key",
          message_timestamp: 30 |> timestamp_from_offset,
          offset: 103,
          topic: "set_topic",
          trigger: trigger
        )

      set_message_1 =
        insert(
          :trigger_kafka_message,
          key: "set_key",
          message_timestamp: 110 |> timestamp_from_offset,
          offset: 101,
          topic: "set_topic",
          trigger: trigger,
          work_order: build(:workorder)
        )

      candidate_set = %{
        trigger_id: trigger.id,
        topic: "set_topic",
        key: "set_key"
      }

      %{
        candidate_set: candidate_set,
        message: set_message_1
      }
    end

    test "returns nil if it can't find a message for the candidate set", %{
      candidate_set: candidate_set
    } do
      no_such_set = candidate_set |> Map.merge(%{key: "no-such-key"})

      assert KafkaTriggers.find_candidate_for(no_such_set) |> Repo.one() == nil
    end

    test "returns earliest message - based on offset - for set", %{
      candidate_set: candidate_set,
      message: message
    } do
      message_id = message.id

      assert %TriggerKafkaMessage{
               id: ^message_id
             } = KafkaTriggers.find_candidate_for(candidate_set) |> Repo.one()
    end

    test "preloads `:workflow`, and `:trigger`", %{
      candidate_set: candidate_set
    } do
      candidate = KafkaTriggers.find_candidate_for(candidate_set) |> Repo.one()

      assert %{
               trigger: %Trigger{
                 workflow: %Workflow{}
               },
               work_order: %WorkOrder{}
             } = candidate
    end
  end

  describe "find_candidate_for/1 - nil key" do
    setup do
      other_trigger = insert(:trigger)
      trigger = insert(:trigger)

      _other_trigger_set_message_1 =
        insert(
          :trigger_kafka_message,
          key: "set_key",
          message_timestamp: 10 |> timestamp_from_offset,
          offset: 1,
          topic: "set_topic",
          trigger: other_trigger
        )

      _other_key_set_message_1 =
        insert(
          :trigger_kafka_message,
          key: "other_set_key",
          message_timestamp: 10 |> timestamp_from_offset,
          offset: 1,
          topic: "set_topic",
          trigger: trigger
        )

      _other_key_set_message_1 =
        insert(
          :trigger_kafka_message,
          key: "set_key",
          message_timestamp: 10 |> timestamp_from_offset,
          offset: 1,
          topic: "other_set_topic",
          trigger: trigger
        )

      _set_message_2 =
        insert(
          :trigger_kafka_message,
          key: nil,
          message_timestamp: 120 |> timestamp_from_offset,
          offset: 102,
          topic: "set_topic",
          trigger: trigger
        )

      _set_message_3 =
        insert(
          :trigger_kafka_message,
          key: nil,
          message_timestamp: 130 |> timestamp_from_offset,
          offset: 103,
          topic: "set_topic",
          trigger: trigger
        )

      set_message_1 =
        insert(
          :trigger_kafka_message,
          key: nil,
          message_timestamp: 110 |> timestamp_from_offset,
          offset: 101,
          topic: "set_topic",
          trigger: trigger,
          work_order: build(:workorder)
        )

      candidate_set = %{
        trigger_id: trigger.id,
        topic: "set_topic",
        key: nil
      }

      %{
        candidate_set: candidate_set,
        message: set_message_1
      }
    end

    test "returns nil if it can't find a message for the candidate set", %{
      candidate_set: candidate_set
    } do
      no_such_set = candidate_set |> Map.merge(%{key: "no-such-key"})

      assert KafkaTriggers.find_candidate_for(no_such_set) |> Repo.one() == nil
    end

    # This can be optimised as Kafka does not guarantee order of messages
    # with nil key
    test "returns earliest message - based on message timestamp - for set", %{
      candidate_set: candidate_set,
      message: message
    } do
      message_id = message.id

      assert %TriggerKafkaMessage{
               id: ^message_id
             } = KafkaTriggers.find_candidate_for(candidate_set) |> Repo.one()
    end

    test "preloads `:workflow`, and `:trigger`", %{
      candidate_set: candidate_set
    } do
      candidate = KafkaTriggers.find_candidate_for(candidate_set) |> Repo.one()

      assert %{
               trigger: %Trigger{
                 workflow: %Workflow{}
               },
               work_order: %WorkOrder{}
             } = candidate
    end
  end

  describe ".successful?/1" do
    test "returns true if work_order is successful", %{} do
      work_order = build(:workorder, state: :success)
      assert KafkaTriggers.successful?(work_order)
    end

    test "returns false if work_order is not successful", %{} do
      states_other_than_success()
      |> Enum.each(fn state ->
        work_order = build(:workorder, state: state)
        refute KafkaTriggers.successful?(work_order)
      end)
    end

    def states_other_than_success do
      ([:rejected, :pending, :running] ++ Run.final_states())
      |> Enum.reject(&(&1 == :success))
    end
  end

  defp timestamp_from_offset(offset) do
    DateTime.utc_now()
    |> DateTime.add(offset)
    |> DateTime.to_unix(:millisecond)
  end

  describe ".enable_disable_triggers/1" do
    setup do
      enabled_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          enabled: true,
          kafka_configuration: new_configuration(index: 1)
        )

      enabled_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          enabled: true,
          kafka_configuration: new_configuration(index: 2)
        )

      disabled_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          enabled: false,
          kafka_configuration: new_configuration(index: 4)
        )

      disabled_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          enabled: false,
          kafka_configuration: new_configuration(index: 5)
        )

      {:ok, pid} = start_supervised(PipelineSupervisor)

      %{
        disabled_trigger_1: disabled_trigger_1,
        disabled_trigger_2: disabled_trigger_2,
        enabled_trigger_1: enabled_trigger_1,
        enabled_trigger_2: enabled_trigger_2,
        pid: pid
      }
    end

    test "adds enabled triggers to the supervisor", %{
      enabled_trigger_1: enabled_trigger_1,
      enabled_trigger_2: enabled_trigger_2,
      pid: pid
    } do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end do
        KafkaTriggers.enable_disable_triggers([
          enabled_trigger_1,
          enabled_trigger_2
        ])

        assert_called(
          Supervisor.start_child(
            pid,
            KafkaTriggers.generate_pipeline_child_spec(enabled_trigger_1)
          )
        )

        assert_called(
          Supervisor.start_child(
            pid,
            KafkaTriggers.generate_pipeline_child_spec(enabled_trigger_2)
          )
        )
      end
    end

    test "removes disabled triggers", %{
      disabled_trigger_1: disabled_trigger_1,
      disabled_trigger_2: disabled_trigger_2,
      pid: pid
    } do
      with_mock Supervisor,
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.enable_disable_triggers([
          disabled_trigger_1,
          disabled_trigger_2
        ])

        assert_called(
          Supervisor.terminate_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_called(
          Supervisor.delete_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_called(
          Supervisor.terminate_child(
            pid,
            disabled_trigger_2.id
          )
        )

        assert_called(
          Supervisor.delete_child(
            pid,
            disabled_trigger_2.id
          )
        )
      end
    end

    test "ignores non-kafka triggers", %{
      enabled_trigger_1: enabled_trigger_1,
      disabled_trigger_1: disabled_trigger_1,
      pid: pid
    } do
      with_mock Supervisor,
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        disabled_non_kafka_trigger =
          insert(
            :trigger,
            type: :cron,
            kafka_configuration: nil,
            enabled: false
          )

        enabled_non_kafka_trigger =
          insert(
            :trigger,
            type: :webhook,
            kafka_configuration: nil,
            enabled: true
          )

        KafkaTriggers.enable_disable_triggers([
          enabled_trigger_1,
          disabled_non_kafka_trigger,
          disabled_trigger_1,
          enabled_non_kafka_trigger
        ])

        assert_called_exactly(
          Supervisor.start_child(
            pid,
            :_
          ),
          1
        )

        assert_called(
          Supervisor.terminate_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_called(
          Supervisor.delete_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_not_called(
          Supervisor.terminate_child(
            pid,
            disabled_non_kafka_trigger.id
          )
        )

        assert_not_called(
          Supervisor.delete_child(
            pid,
            disabled_non_kafka_trigger.id
          )
        )
      end
    end
  end

  describe ".generate_pipeline_child_spec/1" do
    test "generates a child spec based on a kafka trigger" do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: new_configuration(index: 1),
          enabled: true
        )

      expected_child_spec = child_spec(trigger: trigger, index: 1)
      actual_child_spec = KafkaTriggers.generate_pipeline_child_spec(trigger)

      assert actual_child_spec == expected_child_spec
    end

    test "generates a child spec based on a kafka trigger that has no auth" do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: new_configuration(index: 1, sasl: false),
          enabled: true
        )

      expected_child_spec = child_spec(trigger: trigger, index: 1, sasl: false)
      actual_child_spec = KafkaTriggers.generate_pipeline_child_spec(trigger)

      assert actual_child_spec == expected_child_spec
    end

    # TODO merge with other configuration method
    defp new_configuration(opts) do
      index = opts |> Keyword.get(:index)
      partition_timestamps = opts |> Keyword.get(:partition_timestamps, %{})
      sasl = opts |> Keyword.get(:sasl, true)
      ssl = opts |> Keyword.get(:ssl, true)

      password = if sasl, do: "secret-#{index}", else: nil
      sasl_type = if sasl, do: "plain", else: nil
      username = if sasl, do: "my-user-#{index}", else: nil

      initial_offset_reset_policy = "171524976732#{index}"

      %{
        connect_timeout: 30 + index,
        group_id: "lightning-#{index}",
        hosts: [["host-#{index}", "9092"], ["other-host-#{index}", "9093"]],
        initial_offset_reset_policy: initial_offset_reset_policy,
        partition_timestamps: partition_timestamps,
        password: password,
        sasl: sasl_type,
        ssl: ssl,
        topics: ["topic-#{index}-1", "topic-#{index}-2"],
        username: username
      }
    end
  end

  describe ".get_kafka_triggers_being_updated/1" do
    setup do
      %{workflow: insert(:workflow) |> Repo.preload(:triggers)}
    end

    test "returns updated kafka trigger ids contained within changeset", %{
      workflow: workflow
    } do
      kafka_configuration = build(:triggers_kafka_configuration)

      kafka_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      cron_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      kafka_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      webhook_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      triggers = [
        {kafka_trigger_1, %{enabled: true}},
        {cron_trigger_1, %{enabled: true}},
        {kafka_trigger_2, %{enabled: true}},
        {webhook_trigger_1, %{enabled: true}}
      ]

      changeset = workflow |> build_changeset(triggers)

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == [
               kafka_trigger_1.id,
               kafka_trigger_2.id
             ]
    end

    test "returns ids for new kafka triggers being inserted", %{
      workflow: workflow
    } do
      kafka_trigger_1_id = Ecto.UUID.generate()
      cron_trigger_1_id = Ecto.UUID.generate()
      kafka_trigger_2_id = Ecto.UUID.generate()
      webhook_trigger_1_id = Ecto.UUID.generate()

      triggers = [
        {%Trigger{}, %{id: kafka_trigger_1_id, type: :kafka}},
        {%Trigger{}, %{id: cron_trigger_1_id, type: :cron}},
        {%Trigger{}, %{id: kafka_trigger_2_id, type: :kafka}},
        {%Trigger{}, %{id: webhook_trigger_1_id, type: :webhook}}
      ]

      changeset = workflow |> build_changeset(triggers)

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == [
               kafka_trigger_1_id,
               kafka_trigger_2_id
             ]
    end

    test "returns empty list if triggers is an empty list", %{
      workflow: workflow
    } do
      changeset = workflow |> build_changeset([])

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == []
    end

    test "returns empty list if triggers is nil", %{
      workflow: workflow
    } do
      changeset =
        workflow
        |> Ecto.Changeset.change(%{name: "foo-bar-baz"})

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == []
    end

    defp build_changeset(workflow, triggers_and_attrs) do
      triggers_changes =
        triggers_and_attrs
        |> Enum.map(fn {trigger, attrs} ->
          Trigger.changeset(trigger, attrs)
        end)

      Ecto.Changeset.change(workflow, triggers: triggers_changes)
    end
  end

  describe ".update_pipeline/1" do
    setup do
      kafka_configuration = build(:triggers_kafka_configuration)

      enabled_trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: kafka_configuration,
          enabled: true
        )

      disabled_trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      child_spec = KafkaTriggers.generate_pipeline_child_spec(enabled_trigger)

      %{
        child_spec: child_spec,
        disabled_trigger: disabled_trigger,
        enabled_trigger: enabled_trigger,
        supervisor: 100_000_001
      }
    end

    test "adds enabled trigger with the correct child spec", %{
      child_spec: child_spec,
      enabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.start_child(supervisor, child_spec))
      end
    end

    test "removes child if trigger is disabled", %{
      disabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor,
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.terminate_child(supervisor, trigger.id))
        assert_called(Supervisor.delete_child(supervisor, trigger.id))

        assert call_sequence() == [:terminate_child, :delete_child]
      end
    end

    test "if trigger is enabled and pipeline is running, removes and adds", %{
      child_spec: child_spec,
      enabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: [
          in_series(
            [supervisor, child_spec],
            [{:error, {:already_started, "other-pid"}}, {:ok, "fake-pid"}]
          )
        ],
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        which_children: fn _sup_pid -> [] end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.terminate_child(supervisor, trigger.id))
        assert_called(Supervisor.delete_child(supervisor, trigger.id))
        assert_called_exactly(Supervisor.start_child(supervisor, child_spec), 2)

        expected_call_sequence = [
          :start_child,
          :terminate_child,
          :delete_child,
          :start_child
        ]

        assert call_sequence() == expected_call_sequence
      end
    end

    test "if trigger is enabled and pipeline is present, removes and adds", %{
      child_spec: child_spec,
      enabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: [
          in_series(
            [supervisor, child_spec],
            [{:error, :already_present}, {:ok, "fake-pid"}]
          )
        ],
        which_children: fn _sup_pid -> [] end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.delete_child(supervisor, trigger.id))
        assert_called_exactly(Supervisor.start_child(supervisor, child_spec), 2)

        expected_call_sequence = [
          :start_child,
          :delete_child,
          :start_child
        ]

        assert call_sequence() == expected_call_sequence
      end
    end

    test "cannot find a trigger with the given trigger id - does nothing", %{
      supervisor: supervisor
    } do
      trigger_id = Ecto.UUID.generate()

      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger_id)

        assert_not_called(Supervisor.terminate_child(:_, :_))
        assert_not_called(Supervisor.delete_child(:_, :_))
        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "enabled trigger exists but is not a kafka trigger - does nothing", %{
      supervisor: supervisor
    } do
      trigger = insert(:trigger, type: :webhook, enabled: true)

      with_mock Supervisor, [:passthrough],
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "disabled trigger exists but is not a kafka trigger - does nothing", %{
      supervisor: supervisor
    } do
      trigger = insert(:trigger, type: :cron, enabled: false)

      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_not_called(Supervisor.terminate_child(:_, :_))
        assert_not_called(Supervisor.delete_child(:_, :_))
      end
    end

    defp call_sequence do
      Supervisor
      |> call_history()
      |> Enum.map(fn {_pid, {_supervisor, call, _args}, _response} ->
        call
      end)
    end
  end

  defp child_spec(opts) do
    trigger = opts |> Keyword.get(:trigger)
    index = opts |> Keyword.get(:index)
    sasl = opts |> Keyword.get(:sasl, true)
    ssl = opts |> Keyword.get(:ssl, true)

    offset_timestamp = "171524976732#{index}" |> String.to_integer()

    %{
      id: trigger.id,
      start: {
        Lightning.KafkaTriggers.Pipeline,
        :start_link,
        [
          [
            connect_timeout: (30 + index) * 1000,
            group_id: "lightning-#{index}",
            hosts: [{"host-#{index}", 9092}, {"other-host-#{index}", 9093}],
            offset_reset_policy: {:timestamp, offset_timestamp},
            trigger_id: trigger.id |> String.to_atom(),
            sasl: sasl_config(index, sasl),
            ssl: ssl,
            topics: ["topic-#{index}-1", "topic-#{index}-2"]
          ]
        ]
      }
    }
  end

  defp configuration(opts) do
    index = opts |> Keyword.get(:index, 1)
    partition_timestamps = opts |> Keyword.get(:partition_timestamps, %{})
    sasl = opts |> Keyword.get(:sasl, true)
    ssl = opts |> Keyword.get(:ssl, true)

    password = if sasl, do: "secret-#{index}", else: nil
    sasl_type = if sasl, do: "plain", else: nil
    username = if sasl, do: "my-user-#{index}", else: nil

    initial_offset_reset_policy = "171524976732#{index}"

    %{
      connect_timeout: 30 + index,
      group_id: "lightning-#{index}",
      hosts: [["host-#{index}", "9092"], ["other-host-#{index}", "9093"]],
      initial_offset_reset_policy: initial_offset_reset_policy,
      partition_timestamps: partition_timestamps,
      password: password,
      sasl: sasl_type,
      ssl: ssl,
      topics: ["topic-#{index}-1", "topic-#{index}-2"],
      username: username
    }
  end

  defp sasl_config(index, true = _sasl) do
    {:plain, "my-user-#{index}", "secret-#{index}"}
  end

  defp sasl_config(_index, false = _sasl), do: nil
end
