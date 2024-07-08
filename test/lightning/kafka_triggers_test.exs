defmodule Lightning.KafkaTriggersTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Mock

  require Lightning.Run

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.Workflows.Trigger

  describe ".start_triggers/0" do
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
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 1} end do
        KafkaTriggers.start_triggers()

        assert_not_called(Supervisor.count_children(:_))
        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "returns :ok if the supervisor is not running" do
      stop_supervised!(PipelineSupervisor)

      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 1} end do
        assert KafkaTriggers.start_triggers() == :ok
      end
    end

    test "returns :ok if supervisor already has chidren" do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 1} end do
        assert KafkaTriggers.start_triggers() == :ok
      end
    end

    test "asks supervisor to start a child for each trigger", %{
      pid: pid,
      trigger_1: trigger_1,
      trigger_2: trigger_2
    } do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 0} end do
        KafkaTriggers.start_triggers()

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
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 0} end do
        KafkaTriggers.start_triggers()

        assert_called(
          Supervisor.start_child(
            pid,
            child_spec(trigger: no_auth_trigger, index: 3, sasl: false)
          )
        )
      end
    end

    test "returns :ok" do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        count_children: fn _sup_pid -> %{specs: 0} end do
        assert KafkaTriggers.start_triggers() == :ok
      end
    end
  end

  describe ".find_enabled_triggers/0" do
    test "returns enabled kafka triggers" do
      trigger_1 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)

      trigger_2 =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: true)

      not_kafka_trigger =
        insert(:trigger, type: :cron, enabled: true)

      not_enabled =
        insert(:trigger, type: :kafka, kafka_configuration: %{}, enabled: false)

      triggers = KafkaTriggers.find_enabled_triggers()

      assert triggers |> contains?(trigger_1)
      assert triggers |> contains?(trigger_2)
      refute triggers |> contains?(not_kafka_trigger)
      refute triggers |> contains?(not_enabled)
    end

    defp contains?(triggers, %Trigger{id: id}) do
      triggers
      |> Enum.any?(&(&1.id == id))
    end
  end

  describe ".determine_offset_reset_policy" do
    test "returns :earliest if 'earliest'" do
      policy =
        "earliest"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :earliest
    end

    test "returns :latest if 'latest'" do
      policy =
        "latest"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :latest
    end

    test "returns policy if timestamp as a string" do
      timestamp = "1715312900123"

      policy =
        timestamp
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == {:timestamp, timestamp |> String.to_integer()}
    end

    test "returns :latest if unrecognised string" do
      policy =
        "woteva"
        |> build_trigger()
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == :latest
    end

    test "returns earliest partition timestamp if data is available" do
      partition_timestamps = %{
        "1" => 1_715_312_900_121,
        "2" => 1_715_312_900_120,
        "3" => 1_715_312_900_123
      }

      policy =
        "earliest"
        |> build_trigger(partition_timestamps)
        |> KafkaTriggers.determine_offset_reset_policy()

      assert policy == {:timestamp, 1_715_312_900_120}
    end

    defp build_trigger(initial_offset_reset, partition_timestamps \\ %{}) do
      # TODO Centralise the generation of config to avoid drift
      kafka_configuration = %{
        group_id: "lightning-1",
        hosts: [["host-1", 9092], ["other-host-1", 9093]],
        initial_offset_reset_policy: initial_offset_reset,
        partition_timestamps: partition_timestamps,
        sasl: nil,
        ssl: false,
        topics: ["bar_topic"]
      }

      build(:trigger, type: :kafka, kafka_configuration: kafka_configuration)
    end
  end

  describe ".build_topic_partition_offset" do
    test "builds based on the proivded message" do
      message = build_broadway_message("foo", 2, 1)
      assert KafkaTriggers.build_topic_partition_offset(message) == "foo_2_1"

      message = build_broadway_message("bar", 4, 2)
      assert KafkaTriggers.build_topic_partition_offset(message) == "bar_4_2"
    end

    defp build_broadway_message(topic, partition, offset) do
      %Broadway.Message{
        data: %{interesting: "stuff"} |> Jason.encode!(),
        metadata: %{
          offset: offset,
          partition: partition,
          key: "",
          headers: [],
          ts: 1_715_164_718_283,
          topic: topic
        },
        acknowledger: nil,
        batcher: :default,
        batch_key: {"bar_topic", 2},
        batch_mode: :bulk,
        status: :ok
      }
    end
  end

  describe ".enable_disable_triggers/1" do
    setup do
      enabled_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          enabled: true,
          kafka_configuration: new_configuration(index: 1)
        )

      enabled_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          enabled: true,
          kafka_configuration: new_configuration(index: 2)
        )

      disabled_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          enabled: false,
          kafka_configuration: new_configuration(index: 4)
        )

      disabled_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          enabled: false,
          kafka_configuration: new_configuration(index: 5)
        )

      {:ok, pid} = start_supervised(PipelineSupervisor)

      %{
        disabled_trigger_1: disabled_trigger_1,
        disabled_trigger_2: disabled_trigger_2,
        enabled_trigger_1: enabled_trigger_1,
        enabled_trigger_2: enabled_trigger_2,
        pid: pid
      }
    end

    test "adds enabled triggers to the supervisor", %{
      enabled_trigger_1: enabled_trigger_1,
      enabled_trigger_2: enabled_trigger_2,
      pid: pid
    } do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end do
        KafkaTriggers.enable_disable_triggers([
          enabled_trigger_1,
          enabled_trigger_2
        ])

        assert_called(
          Supervisor.start_child(
            pid,
            KafkaTriggers.generate_pipeline_child_spec(enabled_trigger_1)
          )
        )

        assert_called(
          Supervisor.start_child(
            pid,
            KafkaTriggers.generate_pipeline_child_spec(enabled_trigger_2)
          )
        )
      end
    end

    test "removes disabled triggers", %{
      disabled_trigger_1: disabled_trigger_1,
      disabled_trigger_2: disabled_trigger_2,
      pid: pid
    } do
      with_mock Supervisor,
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.enable_disable_triggers([
          disabled_trigger_1,
          disabled_trigger_2
        ])

        assert_called(
          Supervisor.terminate_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_called(
          Supervisor.delete_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_called(
          Supervisor.terminate_child(
            pid,
            disabled_trigger_2.id
          )
        )

        assert_called(
          Supervisor.delete_child(
            pid,
            disabled_trigger_2.id
          )
        )
      end
    end

    test "ignores non-kafka triggers", %{
      enabled_trigger_1: enabled_trigger_1,
      disabled_trigger_1: disabled_trigger_1,
      pid: pid
    } do
      with_mock Supervisor,
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        disabled_non_kafka_trigger =
          insert(
            :trigger,
            type: :cron,
            kafka_configuration: nil,
            enabled: false
          )

        enabled_non_kafka_trigger =
          insert(
            :trigger,
            type: :webhook,
            kafka_configuration: nil,
            enabled: true
          )

        KafkaTriggers.enable_disable_triggers([
          enabled_trigger_1,
          disabled_non_kafka_trigger,
          disabled_trigger_1,
          enabled_non_kafka_trigger
        ])

        assert_called_exactly(
          Supervisor.start_child(
            pid,
            :_
          ),
          1
        )

        assert_called(
          Supervisor.terminate_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_called(
          Supervisor.delete_child(
            pid,
            disabled_trigger_1.id
          )
        )

        assert_not_called(
          Supervisor.terminate_child(
            pid,
            disabled_non_kafka_trigger.id
          )
        )

        assert_not_called(
          Supervisor.delete_child(
            pid,
            disabled_non_kafka_trigger.id
          )
        )
      end
    end
  end

  describe ".generate_pipeline_child_spec/1" do
    test "generates a child spec based on a kafka trigger" do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: new_configuration(index: 1),
          enabled: true
        )

      expected_child_spec = child_spec(trigger: trigger, index: 1)
      actual_child_spec = KafkaTriggers.generate_pipeline_child_spec(trigger)

      assert actual_child_spec == expected_child_spec
    end

    test "generates a child spec based on a kafka trigger that has no auth" do
      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: new_configuration(index: 1, sasl: false),
          enabled: true
        )

      expected_child_spec = child_spec(trigger: trigger, index: 1, sasl: false)
      actual_child_spec = KafkaTriggers.generate_pipeline_child_spec(trigger)

      assert actual_child_spec == expected_child_spec
    end

    # TODO merge with other configuration method
    defp new_configuration(opts) do
      index = opts |> Keyword.get(:index)
      partition_timestamps = opts |> Keyword.get(:partition_timestamps, %{})
      sasl = opts |> Keyword.get(:sasl, true)
      ssl = opts |> Keyword.get(:ssl, true)

      password = if sasl, do: "secret-#{index}", else: nil
      sasl_type = if sasl, do: "plain", else: nil
      username = if sasl, do: "my-user-#{index}", else: nil

      initial_offset_reset_policy = "171524976732#{index}"

      %{
        connect_timeout: 30 + index,
        group_id: "lightning-#{index}",
        hosts: [["host-#{index}", "9092"], ["other-host-#{index}", "9093"]],
        initial_offset_reset_policy: initial_offset_reset_policy,
        partition_timestamps: partition_timestamps,
        password: password,
        sasl: sasl_type,
        ssl: ssl,
        topics: ["topic-#{index}-1", "topic-#{index}-2"],
        username: username
      }
    end
  end

  describe ".get_kafka_triggers_being_updated/1" do
    setup do
      %{workflow: insert(:workflow) |> Repo.preload(:triggers)}
    end

    test "returns updated kafka trigger ids contained within changeset", %{
      workflow: workflow
    } do
      kafka_configuration = build(:triggers_kafka_configuration)

      kafka_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      cron_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      kafka_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      webhook_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      triggers = [
        {kafka_trigger_1, %{enabled: true}},
        {cron_trigger_1, %{enabled: true}},
        {kafka_trigger_2, %{enabled: true}},
        {webhook_trigger_1, %{enabled: true}}
      ]

      changeset = workflow |> build_changeset(triggers)

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == [
               kafka_trigger_1.id,
               kafka_trigger_2.id
             ]
    end

    test "returns ids for new kafka triggers being inserted", %{
      workflow: workflow
    } do
      kafka_trigger_1_id = Ecto.UUID.generate()
      cron_trigger_1_id = Ecto.UUID.generate()
      kafka_trigger_2_id = Ecto.UUID.generate()
      webhook_trigger_1_id = Ecto.UUID.generate()

      triggers = [
        {%Trigger{}, %{id: kafka_trigger_1_id, type: :kafka}},
        {%Trigger{}, %{id: cron_trigger_1_id, type: :cron}},
        {%Trigger{}, %{id: kafka_trigger_2_id, type: :kafka}},
        {%Trigger{}, %{id: webhook_trigger_1_id, type: :webhook}}
      ]

      changeset = workflow |> build_changeset(triggers)

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == [
               kafka_trigger_1_id,
               kafka_trigger_2_id
             ]
    end

    test "returns empty list if triggers is an empty list", %{
      workflow: workflow
    } do
      changeset = workflow |> build_changeset([])

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == []
    end

    test "returns empty list if triggers is nil", %{
      workflow: workflow
    } do
      changeset =
        workflow
        |> Ecto.Changeset.change(%{name: "foo-bar-baz"})

      assert KafkaTriggers.get_kafka_triggers_being_updated(changeset) == []
    end

    defp build_changeset(workflow, triggers_and_attrs) do
      triggers_changes =
        triggers_and_attrs
        |> Enum.map(fn {trigger, attrs} ->
          Trigger.changeset(trigger, attrs)
        end)

      Ecto.Changeset.change(workflow, triggers: triggers_changes)
    end
  end

  describe ".update_pipeline/1" do
    setup do
      kafka_configuration = build(:triggers_kafka_configuration)

      enabled_trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: kafka_configuration,
          enabled: true
        )

      disabled_trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      child_spec = KafkaTriggers.generate_pipeline_child_spec(enabled_trigger)

      %{
        child_spec: child_spec,
        disabled_trigger: disabled_trigger,
        enabled_trigger: enabled_trigger,
        supervisor: 100_000_001
      }
    end

    test "adds enabled trigger with the correct child spec", %{
      child_spec: child_spec,
      enabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.start_child(supervisor, child_spec))
      end
    end

    test "removes child if trigger is disabled", %{
      disabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor,
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.terminate_child(supervisor, trigger.id))
        assert_called(Supervisor.delete_child(supervisor, trigger.id))

        assert call_sequence() == [:terminate_child, :delete_child]
      end
    end

    test "if trigger is enabled and pipeline is running, removes and adds", %{
      child_spec: child_spec,
      enabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: [
          in_series(
            [supervisor, child_spec],
            [{:error, {:already_started, "other-pid"}}, {:ok, "fake-pid"}]
          )
        ],
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        which_children: fn _sup_pid -> [] end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.terminate_child(supervisor, trigger.id))
        assert_called(Supervisor.delete_child(supervisor, trigger.id))
        assert_called_exactly(Supervisor.start_child(supervisor, child_spec), 2)

        expected_call_sequence = [
          :start_child,
          :terminate_child,
          :delete_child,
          :start_child
        ]

        assert call_sequence() == expected_call_sequence
      end
    end

    test "if trigger is enabled and pipeline is present, removes and adds", %{
      child_spec: child_spec,
      enabled_trigger: trigger,
      supervisor: supervisor
    } do
      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: [
          in_series(
            [supervisor, child_spec],
            [{:error, :already_present}, {:ok, "fake-pid"}]
          )
        ],
        which_children: fn _sup_pid -> [] end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_called(Supervisor.delete_child(supervisor, trigger.id))
        assert_called_exactly(Supervisor.start_child(supervisor, child_spec), 2)

        expected_call_sequence = [
          :start_child,
          :delete_child,
          :start_child
        ]

        assert call_sequence() == expected_call_sequence
      end
    end

    test "cannot find a trigger with the given trigger id - does nothing", %{
      supervisor: supervisor
    } do
      trigger_id = Ecto.UUID.generate()

      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger_id)

        assert_not_called(Supervisor.terminate_child(:_, :_))
        assert_not_called(Supervisor.delete_child(:_, :_))
        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "enabled trigger exists but is not a kafka trigger - does nothing", %{
      supervisor: supervisor
    } do
      trigger = insert(:trigger, type: :webhook, enabled: true)

      with_mock Supervisor, [:passthrough],
        start_child: fn _sup_pid, _child_spec -> {:ok, "fake-pid"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_not_called(Supervisor.start_child(:_, :_))
      end
    end

    test "disabled trigger exists but is not a kafka trigger - does nothing", %{
      supervisor: supervisor
    } do
      trigger = insert(:trigger, type: :cron, enabled: false)

      with_mock Supervisor, [:passthrough],
        delete_child: fn _sup_pid, _child_id -> {:ok, "anything"} end,
        terminate_child: fn _sup_pid, _child_id -> {:ok, "anything"} end do
        KafkaTriggers.update_pipeline(supervisor, trigger.id)

        assert_not_called(Supervisor.terminate_child(:_, :_))
        assert_not_called(Supervisor.delete_child(:_, :_))
      end
    end

    defp call_sequence do
      Supervisor
      |> call_history()
      |> Enum.map(fn {_pid, {_supervisor, call, _args}, _response} ->
        call
      end)
    end
  end

  defp child_spec(opts) do
    trigger = opts |> Keyword.get(:trigger)
    index = opts |> Keyword.get(:index)
    sasl = opts |> Keyword.get(:sasl, true)
    ssl = opts |> Keyword.get(:ssl, true)

    offset_timestamp = "171524976732#{index}" |> String.to_integer()

    %{
      id: trigger.id,
      start: {
        Lightning.KafkaTriggers.Pipeline,
        :start_link,
        [
          [
            connect_timeout: (30 + index) * 1000,
            group_id: "lightning-#{index}",
            hosts: [{"host-#{index}", 9092}, {"other-host-#{index}", 9093}],
            offset_reset_policy: {:timestamp, offset_timestamp},
            trigger_id: trigger.id |> String.to_atom(),
            sasl: sasl_config(index, sasl),
            ssl: ssl,
            topics: ["topic-#{index}-1", "topic-#{index}-2"]
          ]
        ]
      }
    }
  end

  defp configuration(opts) do
    index = opts |> Keyword.get(:index, 1)
    partition_timestamps = opts |> Keyword.get(:partition_timestamps, %{})
    sasl = opts |> Keyword.get(:sasl, true)
    ssl = opts |> Keyword.get(:ssl, true)

    password = if sasl, do: "secret-#{index}", else: nil
    sasl_type = if sasl, do: "plain", else: nil
    username = if sasl, do: "my-user-#{index}", else: nil

    initial_offset_reset_policy = "171524976732#{index}"

    %{
      connect_timeout: 30 + index,
      group_id: "lightning-#{index}",
      hosts: [["host-#{index}", "9092"], ["other-host-#{index}", "9093"]],
      initial_offset_reset_policy: initial_offset_reset_policy,
      partition_timestamps: partition_timestamps,
      password: password,
      sasl: sasl_type,
      ssl: ssl,
      topics: ["topic-#{index}-1", "topic-#{index}-2"],
      username: username
    }
  end

  defp sasl_config(index, true = _sasl) do
    {:plain, "my-user-#{index}", "secret-#{index}"}
  end

  defp sasl_config(_index, false = _sasl), do: nil
end
