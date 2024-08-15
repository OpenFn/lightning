defmodule Lightning.KafkaTriggers.EventListenerTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.EventListener
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerPersistenceFailure

  import Mox

  import Mock

  # This is needed to ensure that the Mox stub is available for the
  # test of start_link/1.
  setup :set_mox_from_context

  setup do
    pid = start_supervised!(PipelineSupervisor, [])
    trigger = build(:trigger)
    timestamp = 1_723_633_665_366

    %{
      state: %{},
      supervisor_pid: pid,
      timestamp: timestamp,
      trigger: trigger
    }
  end

  test "start_link/1 starts the event listener" do
    assert {:ok, _pid} = EventListener.start_link([])
  end

  test "init/1 subscribes to the Kafka trigger updated topic", %{
    trigger: trigger
  } do
    trigger_id = trigger.id

    assert EventListener.init([]) == {:ok, %{}}

    Events.kafka_trigger_updated(trigger_id)

    assert_receive %KafkaTriggerUpdated{trigger_id: ^trigger_id}
  end

  test "init/1 subscribes to the Kafka trigger persistence failure topic", %{
    timestamp: timestamp,
    trigger: trigger
  } do
    trigger_id = trigger.id

    assert EventListener.init([]) == {:ok, %{}}

    Events.kafka_trigger_persistence_failure(trigger_id, timestamp)

    assert_receive %KafkaTriggerPersistenceFailure{
      trigger_id: ^trigger_id,
      timestamp: ^timestamp
    }
  end

  describe "handle_info/1 - KafkaTriggerUpdated" do
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

  describe "handle_info/1 - KafkaTriggerPersistenceFailure" do
    test "rolls the trigger's pipeline back to timestamp", %{
      supervisor_pid: pid,
      state: state,
      timestamp: timestamp,
      trigger: trigger
    } do
      with_mock KafkaTriggers,
        rollback_pipeline: fn _supervisor, _trigger, _timestamp ->
          {:ok, "fake-pid"}
        end do
        EventListener.handle_info(
          %KafkaTriggerPersistenceFailure{
            trigger_id: trigger.id,
            timestamp: timestamp
          },
          state
        )

        assert_called(
          KafkaTriggers.rollback_pipeline(pid, trigger.id, timestamp)
        )
      end
    end

    test "returns the appropriate_response", %{
      state: state,
      timestamp: timestamp,
      trigger: trigger
    } do
      with_mock KafkaTriggers,
        rollback_pipeline: fn _supervisor, _trigger, _timestamp ->
          {:ok, "fake-pid"}
        end do
        response =
          EventListener.handle_info(
            %KafkaTriggerPersistenceFailure{
              trigger_id: trigger.id,
              timestamp: timestamp
            },
            state
          )

        assert response == {:noreply, state}
      end
    end

    test "ignores non-KafkaTriggerPersistenceFailure events", %{
      state: state
    } do
      with_mock KafkaTriggers,
        rollback_pipeline: fn _supervisor, _trigger, _timestamp ->
          {:ok, "fake-pid"}
        end do
        assert {:noreply, ^state} = EventListener.handle_info("huh?", state)

        assert_not_called(KafkaTriggers.rollback_pipeline(:_, :_, :_))
      end
    end

    test "does nothing if the supervisor is not running", %{
      state: state,
      timestamp: timestamp,
      trigger: trigger
    } do
      stop_supervised!(PipelineSupervisor)

      with_mock KafkaTriggers,
        rollback_pipeline: fn _supervisor, _trigger, _timestamp ->
          {:ok, "fake-pid"}
        end do
        EventListener.handle_info(
          %KafkaTriggerPersistenceFailure{
            trigger_id: trigger.id,
            timestamp: timestamp
          },
          state
        )

        assert_not_called(KafkaTriggers.rollback_pipeline(:_, :_, :_))
      end
    end
  end
end
