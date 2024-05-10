defmodule Lightning.KafkaTriggers.PipelineWorkerTest do
  use Lightning.DataCase

  import Mock

  alias Lightning.KafkaTriggers.Pipeline
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.KafkaTriggers.PipelineWorker

  describe ".perform/1" do
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
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 1} end
        ] do

        perform_job(PipelineWorker, %{})

        assert_not_called(Supervisor.count_children(:_))
        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "returns :ok if the supervisor is not running" do
      stop_supervised!(PipelineSupervisor)

      with_mock Supervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 1} end
        ] do

        assert perform_job(PipelineWorker, %{}) == :ok
      end
    end

    test "does not start children if supervisor already has children", %{
      pid: pid
    } do
      with_mock Supervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 1} end
        ] do

        perform_job(PipelineWorker, %{})

        assert_called(Supervisor.count_children(pid))
        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "returns :ok if supervisor already has chidren" do
      with_mock Supervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 1} end
        ] do

        assert perform_job(PipelineWorker, %{}) == :ok
      end
    end

    test "asks supervisor to start a child for each trigger", %{
      pid: pid,
      trigger_1: trigger_1,
      trigger_2: trigger_2
    } do
      with_mock Supervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 0} end
        ] do

        perform_job(PipelineWorker, %{})

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
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 0} end
        ] do

        perform_job(PipelineWorker, %{})

        assert_called(
          Supervisor.start_child(
            pid,
            child_spec(trigger: no_auth_trigger, index: 3, sasl: false)
          )
        )
      end
    end

    # test "uses earliest partition timestamp for offset if there is data", %{
    #   pid: pid
    # } do
    #
    # end

    test "returns :ok" do
      with_mock Supervisor,
        [
          start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
          count_children: fn _sup_pid -> %{specs: 0} end
        ] do
        assert perform_job(PipelineWorker, %{}) == :ok
      end
    end

    defp configuration(opts) do
      index = opts |> Keyword.get(:index)
      partition_timestamps = opts |> Keyword.get(:partition_timestamps, %{})
      sasl = opts |> Keyword.get(:sasl, true)
      ssl = opts |> Keyword.get(:ssl, true)

      sasl_config = if sasl do
                      ["plain", "my-user-#{index}", "secret-#{index}"]
                    else
                      nil
                    end

      initial_offset_reset_policy = "171524976732#{index}" |> String.to_integer()

      %{
        "group_id" => "lightning-#{index}",
        "hosts" => [["host-#{index}", 9092], ["other-host-#{index}", 9093]],
        "initial_offset_reset_policy" => initial_offset_reset_policy,
        "partition_timestamps" => partition_timestamps,
        "sasl" => sasl_config,
        "ssl" => ssl,
        "topics" => ["topic-#{index}-1", "topic-#{index}-2"]
      }
    end

    defp child_spec(opts) do
      trigger = opts |> Keyword.get(:trigger)
      index = opts |> Keyword.get(:index)
      offset_reset_policy =
        opts
        |> Keyword.get(
          :offset_reset_policy,
          "171524976732#{index}" |> String.to_integer()
        )
      sasl = opts |> Keyword.get(:sasl, true)
      ssl = opts |> Keyword.get(:ssl, true)

      %{
        id: trigger.id,
        start: {
          Pipeline,
          :start_link,
          [
            [
              group_id: "lightning-#{index}",
              hosts: [{"host-#{index}", 9092}, {"other-host-#{index}", 9093}],
              offset_reset_policy: offset_reset_policy,
              trigger_id: trigger.id |> String.to_atom(),
              sasl: sasl_config(index, sasl),
              ssl: ssl,
              topics: ["topic-#{index}-1", "topic-#{index}-2"]
            ]
          ]
        }
      }
    end
  end

  defp sasl_config(index, true = _sasl) do
    {"plain", "my-user-#{index}", "secret-#{index}"}
  end

  defp sasl_config(_index, false = _sasl), do: nil
end
