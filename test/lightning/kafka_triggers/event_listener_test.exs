defmodule Lightning.KafkaTriggers.EventListenerTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers.EventListener
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated

  import Mox

  # This is needed to ensure that the Mox stub is available for the
  # test of start_link/1.
  setup :set_mox_from_context

  setup do
     pid = start_supervised!(PipelineSupervisor, [])

    %{supervisor_pid: pid}
  end

  test "start_link/1 starts the event listener" do
    assert {:ok, _pid} = EventListener.start_link([])
  end

  test "init/1 subscribes to the Kafka triggers topic" do
    trigger = build(:trigger)

    assert EventListener.init([]) == {:ok, %{}}

    Events.kafka_trigger_updated(trigger)

    assert_receive %KafkaTriggerUpdated{trigger: ^trigger}
  end

  test "handle_info/1 updates the trigger's pipeline", %{
    supervisor_pid: pid
  } do
    trigger = insert(:trigger)

    trigger_id = trigger.id

    EventListener.handle_info(%KafkaTriggerUpdated{trigger: trigger}, %{})

    assert [{^trigger_id, _child, _type, _modules}] =
      Supervisor.which_children(pid)
  end
end
