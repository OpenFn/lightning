defmodule Lightning.KafkaTriggers.MessageHandlingTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Mock
  import Mox

  require Lightning.Run

  alias Ecto.Multi
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Invocation
  alias Lightning.KafkaTriggers.MessageCandidateSet
  alias Lightning.KafkaTriggers.MessageHandling
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Run
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  describe ".find_message_candidate_sets" do
    test "returns distinct combinations of trigger, topic, non-nil key" do
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

      sets = MessageHandling.find_message_candidate_sets()

      assert sets |> Enum.count() == 4

      assert [%{trigger_id: _, topic: _, key: _} | _other] = sets

      assert sets |> number_of_sets_for(message) == 1
      assert sets |> number_of_sets_for(different_key) == 1
      assert sets |> number_of_sets_for(nil_key) == 0
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

  describe ".find_nil_key_message_ids/0" do
    setup do
      message_1 = insert(:trigger_kafka_message, topic: "topic-1", key: nil)
      message_2 = insert(:trigger_kafka_message, topic: "topic-2", key: nil)

      _not_nil_key_message =
        insert(
          :trigger_kafka_message,
          topic: "topic-3",
          key: "not-nil"
        )

      %{
        message_1: message_1,
        message_2: message_2
      }
    end

    test "returns the ids of all TriggerKafkaMessage instances with nil keys", %{
      message_1: message_1,
      message_2: message_2
    } do
      expected = [message_1.id, message_2.id] |> Enum.sort()

      result = MessageHandling.find_nil_key_message_ids()

      assert result |> Enum.sort() == expected
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

      candidate_set = %MessageCandidateSet{
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

    setup [:stub_usage_limiter_ok, :verify_on_exit!]

    test "returns :ok but does nothing if there is no candidate for the set", %{
      candidate_set: candidate_set
    } do
      no_such_set = candidate_set |> Map.merge(%{key: "no-such-key"})

      assert MessageHandling.process_candidate_for(no_such_set) == :ok
    end

    test "if candidate exists sans work_order, creates work_order", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      %{trigger: %{workflow: workflow} = trigger} = message_1
      project_id = workflow.project_id

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

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
               state: :pending,
               trigger: ^trigger,
               workflow: ^workflow
             } = work_order
    end

    test "creates a rejected work order if run creation is constrained", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      %{trigger: %{workflow: workflow} = trigger} = message_1
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :too_many_runs,
         %Message{text: "Too many runs in the last minute"}}
      end)

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

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
               state: :rejected,
               trigger: ^trigger,
               workflow: ^workflow
             } = work_order
    end

    test "does not create a workorder if workorder creation is constrained", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      %{trigger: %{workflow: workflow}} = message_1
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      expected =
        message_1.processing_data
        |> Map.merge(%{"errors" => ["Runs limit exceeded"]})

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

      %{work_order_id: nil, processing_data: processing_data} =
        TriggerKafkaMessage
        |> Repo.get(message_1.id)

      assert processing_data == expected
    end

    test "candidate - no workorder - not JSON - error message - no creation", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      message_1
      |> TriggerKafkaMessage.changeset(%{data: "not a JSON object"})
      |> Repo.update!()

      expected =
        message_1.processing_data
        |> Map.merge(%{"errors" => ["Data is not a JSON object"]})

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

      %{work_order_id: nil, processing_data: processing_data} =
        TriggerKafkaMessage
        |> Repo.get(message_1.id)

      assert processing_data == expected
    end

    test "candidate - no workorder - not a map - error message - no creation", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      message_1
      |> TriggerKafkaMessage.changeset(%{data: "\"not a JSON object\""})
      |> Repo.update!()

      expected =
        message_1.processing_data
        |> Map.merge(%{"errors" => ["Data is not a JSON object"]})

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

      %{work_order_id: nil, processing_data: processing_data} =
        TriggerKafkaMessage
        |> Repo.get(message_1.id)

      assert processing_data == expected
    end

    test "candidate - no workorder - valid data - has errors - no creation", %{
      candidate_set: candidate_set,
      message_1: message_1
    } do
      message_1
      |> TriggerKafkaMessage.changeset(%{
        processing_data: %{
          "errors" => ["Anything"],
          "other" => ["Stuff"]
        }
      })
      |> Repo.update!()

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

      assert %{work_order_id: nil} =
               TriggerKafkaMessage |> Repo.get(message_1.id)
    end

    test "if candidate has successful work_order, deletes candidate", %{
      candidate_set: candidate_set,
      message_1: message_1,
      message_2: message_2,
      other_message: other_message
    } do
      MessageHandling.process_candidate_for(candidate_set)

      updated_message_1 =
        TriggerKafkaMessage
        |> Repo.get(message_1.id)
        |> Repo.preload(:work_order)

      %{work_order: work_order} = updated_message_1

      work_order
      |> WorkOrder.changeset(%{state: :success})
      |> Repo.update()

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

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
      # Link a WorkOrder
      assert MessageHandling.process_candidate_for(candidate_set) == :ok

      assert MessageHandling.process_candidate_for(candidate_set) == :ok

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
          MessageHandling.process_candidate_for(candidate_set)
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

      candidate_set = %MessageCandidateSet{
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

      assert MessageHandling.find_candidate_for(no_such_set) |> Repo.one() == nil
    end

    test "returns earliest message - based on offset - for set", %{
      candidate_set: candidate_set,
      message: message
    } do
      message_id = message.id

      assert %TriggerKafkaMessage{
               id: ^message_id
             } = MessageHandling.find_candidate_for(candidate_set) |> Repo.one()
    end

    test "preloads `:workflow`, and `:trigger`", %{
      candidate_set: candidate_set
    } do
      candidate = MessageHandling.find_candidate_for(candidate_set) |> Repo.one()

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

      candidate_set = %MessageCandidateSet{
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

      assert MessageHandling.find_candidate_for(no_such_set) |> Repo.one() == nil
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
             } = MessageHandling.find_candidate_for(candidate_set) |> Repo.one()
    end

    test "preloads `:workflow`, and `:trigger`", %{
      candidate_set: candidate_set
    } do
      candidate = MessageHandling.find_candidate_for(candidate_set) |> Repo.one()

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
      assert MessageHandling.successful?(work_order)
    end

    test "returns false if work_order is not successful", %{} do
      states_other_than_success()
      |> Enum.each(fn state ->
        work_order = build(:workorder, state: state)
        refute MessageHandling.successful?(work_order)
      end)
    end

    def states_other_than_success do
      ([:rejected, :pending, :running] ++ Run.final_states())
      |> Enum.reject(&(&1 == :success))
    end
  end

  describe ".process_message_for/1" do
    setup do
      trigger = insert(:trigger, type: :kafka)

      other_message =
        insert(
          :trigger_kafka_message,
          key: nil,
          offset: 1,
          topic: "other-test-topic",
          work_order: nil
        )

      message =
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
          trigger: trigger,
          topic: "test-topic",
          work_order: nil
        )

      %{
        message: message,
        other_message: other_message
      }
    end

    setup [:stub_usage_limiter_ok, :verify_on_exit!]

    test "returns :ok, does nothing if message does not exist", %{
      message: message
    } do
      message |> Repo.delete!()

      assert MessageHandling.process_message_for(message.id) == :ok
    end

    test "links to a work_order if message is not already linked", %{
      message: message
    } do
      %{trigger: %{workflow: workflow} = trigger} = message
      project_id = workflow.project_id

      assert MessageHandling.process_message_for(message.id) == :ok

      %{work_order: work_order} =
        TriggerKafkaMessage
        |> Repo.get(message.id)
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
               state: :pending,
               trigger: ^trigger,
               workflow: ^workflow
             } = work_order
    end

    test "creates a rejected work order if run creation is constrained", %{
      message: message
    } do
      %{trigger: %{workflow: workflow} = trigger} = message
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :too_many_runs,
         %Message{text: "Too many runs in the last minute"}}
      end)

      assert MessageHandling.process_message_for(message.id) == :ok

      %{work_order: work_order} =
        TriggerKafkaMessage
        |> Repo.get(message.id)
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
               state: :rejected,
               trigger: ^trigger,
               workflow: ^workflow
             } = work_order
    end

    test "does not create a workorder if workorder creation is constrained", %{
      message: message
    } do
      %{trigger: %{workflow: workflow}} = message
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      expected =
        message.processing_data
        |> Map.merge(%{"errors" => ["Runs limit exceeded"]})

      assert MessageHandling.process_message_for(message.id) == :ok

      %{work_order_id: nil, processing_data: processing_data} =
        TriggerKafkaMessage
        |> Repo.get(message.id)

      assert processing_data == expected
    end

    test "message - no workorder - not JSON - error message - no creation", %{
      message: message
    } do
      message
      |> TriggerKafkaMessage.changeset(%{data: "not a JSON object"})
      |> Repo.update!()

      expected =
        message.processing_data
        |> Map.merge(%{"errors" => ["Data is not a JSON object"]})

      assert MessageHandling.process_message_for(message.id) == :ok

      %{work_order_id: nil, processing_data: processing_data} =
        TriggerKafkaMessage
        |> Repo.get(message.id)

      assert processing_data == expected
    end

    test "message - no workorder - not a map - error message - no creation", %{
      message: message
    } do
      message
      |> TriggerKafkaMessage.changeset(%{data: "\"not a JSON object\""})
      |> Repo.update!()

      expected =
        message.processing_data
        |> Map.merge(%{"errors" => ["Data is not a JSON object"]})

      assert MessageHandling.process_message_for(message.id) == :ok

      %{work_order_id: nil, processing_data: processing_data} =
        TriggerKafkaMessage
        |> Repo.get(message.id)

      assert processing_data == expected
    end

    test "message - no workorder - valid data - has errors - no creation", %{
      message: message
    } do
      message
      |> TriggerKafkaMessage.changeset(%{
        processing_data: %{
          "errors" => ["Anything"],
          "other" => ["Stuff"]
        }
      })
      |> Repo.update!()

      assert MessageHandling.process_message_for(message.id) == :ok

      assert %{work_order_id: nil} =
               TriggerKafkaMessage |> Repo.get(message.id)
    end

    test "if message has successful work_order, deletes candidate", %{
      message: message,
      other_message: other_message
    } do
      MessageHandling.process_message_for(message.id)

      updated_message_1 =
        TriggerKafkaMessage
        |> Repo.get(message.id)
        |> Repo.preload(:work_order)

      %{work_order: work_order} = updated_message_1

      work_order
      |> WorkOrder.changeset(%{state: :success})
      |> Repo.update()

      assert MessageHandling.process_message_for(message.id) == :ok

      assert TriggerKafkaMessage |> Repo.get(message.id) == nil
      assert TriggerKafkaMessage |> Repo.get(other_message.id) != nil
    end

    test "if message does not have successful work_order, does not delete", %{
      message: message,
      other_message: other_message
    } do
      # Link a WorkOrder
      assert MessageHandling.process_message_for(message.id) == :ok

      assert MessageHandling.process_message_for(message.id) == :ok

      assert TriggerKafkaMessage |> Repo.get(message.id) != nil
      assert TriggerKafkaMessage |> Repo.get(other_message.id) != nil
    end

    test "rolls back if an error occurs", %{
      message: message
    } do
      with_mock(
        TriggerKafkaMessage,
        [:passthrough],
        changeset: fn _message, _changes -> raise "rollback" end
      ) do
        assert_raise RuntimeError, ~r/rollback/, fn ->
          MessageHandling.process_message_for(message.id)
        end
      end

      assert WorkOrder |> Repo.all() == []
    end
  end

  describe ".persist_message/3" do
    setup do
      message = build_broadway_message()

      trigger = insert(:trigger, type: :kafka)

      record_changeset =
        TriggerKafkaMessageRecord.changeset(
          %TriggerKafkaMessageRecord{},
          %{topic_partition_offset: "foo-bar-baz", trigger_id: trigger.id}
        )

      multi =
        Multi.new()
        |> Multi.insert(:record, record_changeset)

      %{message: message, multi: multi, trigger: trigger}
    end

    test "creates the WorkOrder", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      MessageHandling.persist_message(multi, trigger.id, message)

      created_workorder =
        WorkOrder
        |> Repo.one()
        |> Repo.preload([
          :trigger,
          :workflow,
          dataclip: Invocation.Query.dataclip_with_body()
        ])

      assert created_workorder.trigger_id == trigger.id
      assert created_workorder.workflow_id == workflow.id
      assert created_workorder.state == :pending

      %{dataclip: dataclip} = created_workorder
      assert dataclip.body["data"] == %{"interesting" => "stuff"}
      assert dataclip.body["request"] == message.metadata |> stringify_keys()
      assert dataclip.type == :kafka
      assert dataclip.project_id == workflow.project_id
    end

    test "executes any other instructions in the multi", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      MessageHandling.persist_message(multi, trigger.id, message)

      assert TriggerKafkaMessageRecord
             |> Repo.get_by(trigger_id: trigger.id) != nil
    end

    test "returns the results of the insertion", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      assert {:ok, work_order} =
               MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.get(work_order.id) != nil
    end

    test "creates a rejected work order if run creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :too_many_runs,
         %Message{text: "Too many runs in the last minute"}}
      end)

      MessageHandling.persist_message(multi, trigger.id, message)

      created_workorder =
        WorkOrder
        |> Repo.one()
        |> Repo.preload([
          :trigger,
          :workflow,
          dataclip: Invocation.Query.dataclip_with_body()
        ])

      assert created_workorder.trigger_id == trigger.id
      assert created_workorder.workflow_id == workflow.id
      assert created_workorder.state == :rejected

      %{dataclip: dataclip} = created_workorder
      assert dataclip.body["data"] == %{"interesting" => "stuff"}
      assert dataclip.body["request"] == message.metadata |> stringify_keys()
      assert dataclip.type == :kafka
      assert dataclip.project_id == workflow.project_id
    end

    test "returns results of the insertion if run creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :too_many_runs,
         %Message{text: "Too many runs in the last minute"}}
      end)

      assert {:ok, work_order} =
               MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.get(work_order.id) != nil
    end

    test "does not create a workorder if workorder creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.all() == []
    end

    test "returns an error response if workorder creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      assert MessageHandling.persist_message(multi, trigger.id, message) ==
               {:error, :work_order_creation_blocked, "Runs limit exceeded"}
    end

    test "does not create a work order if data is not valid JSON", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "not a JSON object")

      MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.all() == []
    end

    test "returns an error if data is not valid JSON", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "not a JSON object")

      assert MessageHandling.persist_message(multi, trigger.id, message) ==
               {:error, :data_is_not_json_object}
    end

    test "does not create a work order if data is not a map", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "\"not a JSON object\"")

      MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.all() == []
    end

    test "returns an error indicating that the data can not be parsed", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "\"not a JSON object\"")

      assert MessageHandling.persist_message(multi, trigger.id, message) ==
               {:error, :data_is_not_json_object}
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
  end

  defp timestamp_from_offset(offset) do
    DateTime.utc_now()
    |> DateTime.add(offset)
    |> DateTime.to_unix(:millisecond)
  end

  # Put this in a helper
  defp stringify_keys(map) do
    map
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, acc ->
      acc |> stringify_key(key, map[key])
    end)
  end

  defp stringify_key(acc, key, val) when is_map(val) and not is_struct(val) do
    acc
    |> Map.merge(%{to_string(key) => stringify_keys(val)})
  end

  defp stringify_key(acc, key, val) do
    acc
    |> Map.merge(%{to_string(key) => val})
  end
end
