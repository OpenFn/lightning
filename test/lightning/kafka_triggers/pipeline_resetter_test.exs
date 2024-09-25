defmodule Lightning.KafkaTriggers.PipelineResetterTest do
  use Lightning.DataCase

  import Mock

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.PipelineResetter

  describe "start_link/1" do
    test "starts the trigger resetter" do
      assert {:ok, _pid} = PipelineResetter.start_link([])
    end

    test "starts the resetter with the name of the module" do
      PipelineResetter.start_link([])

      assert GenServer.whereis(PipelineResetter) |> Process.alive?()
    end

    test "starts with an empty state" do
      {:ok, pid} = PipelineResetter.start_link([])

      assert :sys.get_state(pid) == %{}
    end
  end

  describe "handle_info/2" do
    setup do
      %{
        state: %{stuff: "happens"},
        timestamp: 1_715_164_718_283,
        trigger_id: "abc-123"
      }
    end
    test "resets the trigger", %{
      state: state,
      timestamp: timestamp,
      trigger_id: trigger_id
    } do
      with_mock KafkaTriggers,
        reset_pipeline: fn _trigger_id, _timestamp -> true end do
        PipelineResetter.handle_info({:reset, {trigger_id, timestamp}}, state)

        assert_called(KafkaTriggers.reset_pipeline(trigger_id, timestamp))
      end
    end

    test "returns :noreply with the state unchanged", %{
      state: state,
      timestamp: timestamp,
      trigger_id: trigger_id
    } do
      with_mock KafkaTriggers,
      reset_pipeline: fn _trigger_id, _timestamp -> true end do
        assert {:noreply, ^state} =
          PipelineResetter.handle_info({:reset, {trigger_id, timestamp}}, state)
      end
    end
  end
end
