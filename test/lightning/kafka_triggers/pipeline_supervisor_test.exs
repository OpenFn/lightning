defmodule Lightning.KafkaTriggers.PipelineSupervisorTest do
  use Lightning.DataCase, async: true

  alias Lightning.KafkaTriggers.PipelineSupervisor

  describe ".start_link/1" do
    test "starts the supervisor with an empty collection of children" do
      assert {:ok, _pid} = start_supervised(PipelineSupervisor)
    end
  end
end
