defmodule Lightning.KafkaTriggers.PipelineWorkerTest do
  use Lightning.DataCase

  import Mock

  alias Lightning.KafkaTriggers.Pipeline
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.KafkaTriggers.PipelineWorker

  describe ".perform/1" do
    setup do
      {:ok, pid} = start_supervised(PipelineSupervisor)

      %{pid: pid}
    end

    test "does not start children if supervisor already has children", %{
      pid: pid
    } do
      with_mock DynamicSupervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 1} end
        ] do

        _trigger_1 =
          insert(
            :trigger,
            type: :kafka,
            kafka_configuration: configuration(1),
            enabled: true
          )
        _trigger_2 =
          insert(
            :trigger,
            type: :kafka,
            kafka_configuration: configuration(2),
            enabled: true
          )

        perform_job(PipelineWorker, %{})

        assert_called(DynamicSupervisor.count_children(pid))
        assert_not_called(DynamicSupervisor.start_child(:_, :_))
      end
    end

    test "returns :ok if supervisor already has chidren" do
      with_mock DynamicSupervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 1} end
        ] do

        _trigger_1 =
          insert(
            :trigger,
            type: :kafka,
            kafka_configuration: configuration(1),
            enabled: true
          )
        _trigger_2 =
          insert(
            :trigger,
            type: :kafka,
            kafka_configuration: configuration(2),
            enabled: true
          )

        assert perform_job(PipelineWorker, %{}) == :ok
      end
    end

    test "asks supervisor to start a child for each trigger", %{
      pid: pid
    } do
      with_mock DynamicSupervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 0} end
        ] do

        trigger_1 =
          insert(
            :trigger,
            type: :kafka,
            kafka_configuration: configuration(1),
            enabled: true
          )
        trigger_2 =
          insert(
            :trigger,
            type: :kafka,
            kafka_configuration: configuration(2),
            enabled: true
          )

        perform_job(PipelineWorker, %{})

        assert_called(
          DynamicSupervisor.start_child(pid, child_spec(trigger_1, 1))
        )
        assert_called(
          DynamicSupervisor.start_child(pid, child_spec(trigger_2, 2))
        )
      end
    end

    test "returns :ok" do
      with_mock DynamicSupervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 0} end
        ] do
        assert perform_job(PipelineWorker, %{}) == :ok
      end
    end

    def configuration(index) do
      %{
        "group_id" => "lightning-#{index}",
        "hosts" => [["host-#{index}", 9092], ["other-host-#{index}", 9093]],
        "topics" => ["topic-#{index}-1", "topic-#{index}-2"]
      }
    end

    def child_spec(trigger, index) do
      %{
        id: trigger.id,
        start: {
          Pipeline,
          :start_link,
          [
            [
              group_id: "lightning-#{index}",
              hosts: [{"host-#{index}", 9092}, {"other-host-#{index}", 9093}],
              name: trigger.id |> String.to_atom(),
              topics: ["topic-#{index}-1", "topic-#{index}-2"]
            ]
          ]
        }
      }
    end
  end
end
