defmodule Lightning.KafkaTriggers.PipelineSupervisorTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.Workflows.Trigger

  describe ".start_link/1" do
    test "starts all enabled Kafka triggers" do
      _trigger_1 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)
      _trigger_2 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)

      Trigger |> Repo.all() |> IO.inspect(label: :test)

      assert {:ok, pid} = start_supervised({PipelineSupervisor, test_pid: self()})

      assert Supervisor.count_children(pid).active == 2
    end
  end
end
