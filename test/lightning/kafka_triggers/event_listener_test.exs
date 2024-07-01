defmodule Lightning.KafkaTriggers.EventListenerTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.EventListener
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated

  import Mox

  import Mock

  # This is needed to ensure that the Mox stub is available for the
  # test of start_link/1.
  setup :set_mox_from_context

  setup do
    pid = start_supervised!(PipelineSupervisor, [])
    trigger = build(:trigger)

    %{
      state: %{},
      supervisor_pid: pid,
      trigger: trigger
    }
  end

  test "start_link/1 starts the event listener" do
    assert {:ok, _pid} = EventListener.start_link([])
  end

  test "init/1 subscribes to the Kafka triggers topic", %{
    trigger: trigger
  } do
    trigger_id = trigger.id

    assert EventListener.init([]) == {:ok, %{}}

    Events.kafka_trigger_updated(trigger)

    assert_receive %KafkaTriggerUpdated{trigger_id: ^trigger_id}
  end

  test "handle_info/1 updates the trigger's pipeline", %{
    supervisor_pid: pid,
    state: state,
    trigger: trigger
  } do
    with_mock KafkaTriggers,
      update_pipeline: fn _supervisor, _trigger -> {:ok, "fake-pid"} end do
      EventListener.handle_info(
        %KafkaTriggerUpdated{trigger_id: trigger.id},
        state
      )

      assert_called(KafkaTriggers.update_pipeline(pid, trigger.id))
    end
  end

  test "handle_info/1 returns appropriate response", %{
    state: state,
    trigger: trigger
  } do
    with_mock KafkaTriggers,
      update_pipeline: fn _supervisor, _trigger -> {:ok, "fake-pid"} end do
      assert {:noreply, ^state} =
               EventListener.handle_info(
                 %KafkaTriggerUpdated{trigger_id: trigger.id},
                 state
               )
    end
  end

  test "handle_info/1 ignores non-KafkaTriggerUpdated events", %{
    state: state
  } do
    with_mock KafkaTriggers,
      update_pipeline: fn _supervisor, _trigger -> {:ok, "fake-pid"} end do
      assert {:noreply, ^state} = EventListener.handle_info("huh?", state)

      assert_not_called(KafkaTriggers.update_pipeline(:_, :_))
    end
  end

  test "handle_info/1 does nothing if PipelineSupervisor is not running", %{
    state: state,
    trigger: trigger
  } do
    stop_supervised!(PipelineSupervisor)

    with_mock KafkaTriggers,
      update_pipeline: fn _supervisor, _trigger -> {:ok, "fake-pid"} end do
      assert {:noreply, ^state} =
               EventListener.handle_info(
                 %KafkaTriggerUpdated{trigger_id: trigger.id},
                 state
               )

      assert_not_called(KafkaTriggers.update_pipeline(:_, :_))
    end
  end
end
