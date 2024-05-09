defmodule Lightning.KafkaTriggers.PipelineTest do
  use Lightning.DataCase

  import Mock

  alias Lightning.KafkaTriggers.Pipeline
  alias Lightning.Workflows.Trigger

  describe ".start_link/1" do
    test "starts a Broadway GenServer process with SASL credentials" do
      group_id = "my_group"
      hosts = [{"localhost", 9092}]
      trigger_id = :my_trigger_id
      sasl = {"plain", "my_username", "my_secret"}
      sasl_expected = {:plain, "my_username", "my_secret"}
      ssl = true
      topics = ["my_topic"]

      with_mock Broadway,
        [start_link: fn _module, _opts -> {:ok, "fake-pid"} end] do

        Pipeline.start_link(
          group_id: group_id,
          hosts: hosts,
          trigger_id: trigger_id,
          sasl: sasl,
          ssl: ssl,
          topics: topics
        )

        assert called Broadway.start_link(
          Pipeline,
          name: trigger_id,
          context: %{
            trigger_id: trigger_id,
          },
          producer: [
            module:
            {
              BroadwayKafka.Producer,
              [
                client_config: [
                  sasl: sasl_expected,
                  ssl: ssl
                ],
                hosts: hosts,
                group_id: group_id,
                topics: topics,
                offset_reset_policy: :earliest
              ]
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
    end

    test "starts a Broadway GenServer process without SASL credentials" do
      group_id = "my_group"
      hosts = [{"localhost", 9092}]
      trigger_id = :my_trigger_id
      sasl = nil
      ssl = true
      topics = ["my_topic"]

      with_mock Broadway,
        [start_link: fn _module, _opts -> {:ok, "fake-pid"} end] do

        Pipeline.start_link(
          group_id: group_id,
          hosts: hosts,
          trigger_id: trigger_id,
          sasl: sasl,
          ssl: ssl,
          topics: topics
        )

        assert called Broadway.start_link(
          Pipeline,
          name: trigger_id,
          context: %{
            trigger_id: trigger_id,
          },
          producer: [
            module:
            {
              BroadwayKafka.Producer,
              [
                client_config: [ssl: ssl],
                hosts: hosts,
                group_id: group_id,
                topics: topics,
                offset_reset_policy: :earliest
              ]
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
      trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 2, ssl: false),
          enabled: true
        )

      context = %{trigger_id: trigger_1.id |> String.to_atom()}

      %{trigger_1: trigger_1, trigger_2: trigger_2, context: context}
    end

    test "returns the message", %{context: context} do
      message = build_broadway_message()

      assert Pipeline.handle_message(nil, message, context) == message
    end

    test "updates the partition timestamp for the trigger", %{
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      context: context
    } do
      message = build_broadway_message()

      Pipeline.handle_message(nil, message, context)

      %{
        kafka_configuration: %{
          "partition_timestamps" => trigger_1_timestamps
        }
      } = Trigger |> Repo.get(trigger_1.id)
      %{
        kafka_configuration: %{
          "partition_timestamps" => trigger_2_timestamps
        }
      } = Trigger |> Repo.get(trigger_2.id)

      assert %{"1" => 1715164718281, "2" => 1715164718283} = trigger_1_timestamps
      assert %{"1" => 1715164718281, "2" => 1715164718282} = trigger_2_timestamps
    end

    defp build_broadway_message do
      %Broadway.Message{
        data: "Bar message 888",
        metadata: %{
          offset: 11,
          partition: 2,
          key: "",
          headers: [],
          ts: 1715164718283,
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

      sasl_config = if sasl do
                      ["plain", "my-user-#{index}", "secret-#{index}"]
                    else
                      nil
                    end

      %{
        "group_id" => "lightning-#{index}",
        "hosts" => [["host-#{index}", 9092], ["other-host-#{index}", 9093]],
        "partition_timestamps" => %{
          "1" => 1715164718281,
          "2" => 1715164718282
        },
        "sasl" => sasl_config,
        "ssl" => ssl,
        "topics" => ["topic-#{index}-1", "topic-#{index}-2"]
      }
    end
  end
end
