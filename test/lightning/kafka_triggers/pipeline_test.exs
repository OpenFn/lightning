defmodule Lightning.KafkaTriggers.PipelineTest do
  use Lightning.DataCase

  import Mock

  alias Lightning.KafkaTriggers.Pipeline

  describe ".start_link/1" do
    test "starts a Broadway GenServer process" do
      group_id = "my_group"
      hosts = [{"localhost", 9092}]
      name = "my_pipeline"
      topics = ["my_topic"]

      with_mock Broadway,
        [start_link: fn _module, _opts -> {:ok, "fake-pid"} end] do

        Pipeline.start_link(
          group_id: group_id,
          hosts: hosts,
          name: name,
          topics: topics
        )

        # IO.inspect(call_history(Broadway))

        assert called Broadway.start_link(
          Pipeline,
          name: name,
          context: %{
            name: name,
          },
          producer: [
            module:
            {
              BroadwayKafka.Producer,
              [
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
end
