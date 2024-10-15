defmodule Lightning.KafkaTriggersTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Mock
  import Mox

  require Lightning.Run

  alias Lightning.AccountsFixtures
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.Events

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

  describe ".build_topic_partition_offset" do
    test "builds based on the provided message" do
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
          kafka_configuration: configuration(index: 1)
        )

      enabled_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          enabled: true,
          kafka_configuration: configuration(index: 2)
        )

      disabled_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          enabled: false,
          kafka_configuration: configuration(index: 4)
        )

      disabled_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          enabled: false,
          kafka_configuration: configuration(index: 5)
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
      number_of_consumers = Lightning.Config.kafka_number_of_consumers()

      assert number_of_consumers != nil

      number_of_processors = Lightning.Config.kafka_number_of_processors()

      assert number_of_processors != nil

      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 1),
          enabled: true
        )

      expected_child_spec =
        child_spec(
          trigger: trigger,
          index: 1,
          number_of_consumers: number_of_consumers,
          number_of_processors: number_of_processors
        )

      actual_child_spec = KafkaTriggers.generate_pipeline_child_spec(trigger)

      assert actual_child_spec == expected_child_spec
    end

    test "generates a child spec based on a kafka trigger that has no auth" do
      number_of_consumers = Lightning.Config.kafka_number_of_consumers()

      assert number_of_consumers != nil

      number_of_processors = Lightning.Config.kafka_number_of_processors()

      assert number_of_processors != nil

      trigger =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: configuration(index: 1, sasl: false),
          enabled: true
        )

      expected_child_spec =
        child_spec(
          trigger: trigger,
          index: 1,
          sasl: false,
          number_of_consumers: number_of_consumers,
          number_of_processors: number_of_processors
        )

      actual_child_spec = KafkaTriggers.generate_pipeline_child_spec(trigger)

      assert actual_child_spec == expected_child_spec
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

  describe "convert_rate_limit" do
    setup :verify_on_exit!

    test "converts rate limit to an integer rate per ten seconds" do
      expect(Lightning.MockConfig, :kafka_number_of_messages_per_second, fn ->
        0.5
      end)

      expected = %{interval: 10_000, messages_per_interval: 5}

      assert KafkaTriggers.convert_rate_limit() == expected
    end

    test "rounds down the number of messages when converting" do
      expect(Lightning.MockConfig, :kafka_number_of_messages_per_second, fn ->
        0.59
      end)

      expected = %{interval: 10_000, messages_per_interval: 5}

      assert KafkaTriggers.convert_rate_limit() == expected
    end
  end

  describe "initial_policy" do
    test "returns :earliest if 'earliest'" do
      trigger = "earliest" |> build_trigger()

      policy = KafkaTriggers.initial_policy(trigger.kafka_configuration)

      assert policy == :earliest
    end

    test "returns :latest if 'latest'" do
      trigger = "latest" |> build_trigger()

      policy = KafkaTriggers.initial_policy(trigger.kafka_configuration)

      assert policy == :latest
    end

    test "returns policy if timestamp as a string" do
      timestamp = "1715312900123"

      trigger = timestamp |> build_trigger()

      policy = KafkaTriggers.initial_policy(trigger.kafka_configuration)

      assert policy == {:timestamp, timestamp |> String.to_integer()}
    end

    test "returns :latest if unrecognised string" do
      trigger = "woteva" |> build_trigger()

      policy = KafkaTriggers.initial_policy(trigger.kafka_configuration)

      assert policy == :latest
    end
  end

  describe ".notify_users_of_trigger_failure/1" do
    setup do
      admin_user = AccountsFixtures.user_fixture()
      owner_user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      _other_trigger = setup_users_for_trigger([{other_user, :admin}])

      trigger =
        setup_users_for_trigger([{admin_user, :admin}, {owner_user, :owner}])

      %{
        admin_user: admin_user,
        other_user: other_user,
        owner_user: owner_user,
        trigger: trigger
      }
    end

    test "sends an email to all associated superusers only", %{
      admin_user: admin_user,
      other_user: other_user,
      owner_user: owner_user,
      trigger: %{id: trigger_id, workflow: workflow}
    } do
      expected_subject = "Kafka trigger failure on #{workflow.name}"

      admin_user_recipient = Swoosh.Email.Recipient.format(admin_user)
      other_user_recipient = Swoosh.Email.Recipient.format(other_user)
      owner_user_recipient = Swoosh.Email.Recipient.format(owner_user)

      KafkaTriggers.notify_users_of_trigger_failure(trigger_id)

      # Swoosh test matchers seem to have a blind spot wrt multiple
      # `deliver` calls.
      assert_received({
        :email,
        %Swoosh.Email{
          subject: subject,
          to: [^admin_user_recipient],
          text_body: body
        }
      })

      assert subject == expected_subject

      timestamp =
        ~r/(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)/
        |> Regex.named_captures(body)
        |> Map.get("ts")
        |> DateTime.from_iso8601()
        |> then(fn {:ok, ts, _offset} -> ts end)

      assert DateTime.diff(DateTime.utc_now(), timestamp, :second) < 2

      assert_received({
        :email,
        %Swoosh.Email{to: [^owner_user_recipient]}
      })

      refute_received({
        :email,
        %Swoosh.Email{to: [^other_user_recipient]}
      })
    end

    test "sets an indicator of when last a notification was sent for trigger", %{
      trigger: %{id: trigger_id}
    } do
      KafkaTriggers.notify_users_of_trigger_failure(trigger_id)

      sent_at =
        :persistent_term.get(
          {:kafka_trigger_failure_notification_sent_at, trigger_id}
        )

      assert DateTime.diff(DateTime.utc_now(), sent_at, :second) < 2
    end

    test "publishes an event wih the notification time", %{
      trigger: %{id: trigger_id}
    } do
      Events.subscribe_to_kafka_trigger_updated()

      KafkaTriggers.notify_users_of_trigger_failure(trigger_id)

      assert_received(%Events.KafkaTriggerNotificationSent{
        trigger_id: ^trigger_id,
        sent_at: sent_at
      })

      assert DateTime.diff(DateTime.utc_now(), sent_at, :second) < 2
    end
  end

  describe ".notify_users_of_trigger_failure/1 - within notification embargo" do
    setup do
      admin_user = AccountsFixtures.user_fixture()
      owner_user = AccountsFixtures.user_fixture()

      trigger =
        setup_users_for_trigger([{admin_user, :admin}, {owner_user, :owner}])

      last_sent_at = DateTime.add(DateTime.utc_now(), -1, :second)

      :persistent_term.put(
        {:kafka_trigger_failure_notification_sent_at, trigger.id},
        last_sent_at
      )

      expect(Lightning.MockConfig, :kafka_notification_embargo_seconds, fn ->
        60
      end)

      %{
        admin_user: admin_user,
        last_sent_at: last_sent_at,
        owner_user: owner_user,
        trigger: trigger
      }
    end

    test "does not send emails if within the notification embargo", %{
      admin_user: admin_user,
      owner_user: owner_user,
      trigger: %{id: trigger_id}
    } do
      admin_user_recipient = Swoosh.Email.Recipient.format(admin_user)
      owner_user_recipient = Swoosh.Email.Recipient.format(owner_user)

      KafkaTriggers.notify_users_of_trigger_failure(trigger_id)

      refute_received({:email, %Swoosh.Email{to: [^admin_user_recipient]}})

      refute_received({:email, %Swoosh.Email{to: [^owner_user_recipient]}})
    end

    test "does not update the indicator if within the notification embargo", %{
      last_sent_at: last_sent_at,
      trigger: %{id: trigger_id}
    } do
      KafkaTriggers.notify_users_of_trigger_failure(trigger_id)

      sent_at =
        :persistent_term.get(
          {:kafka_trigger_failure_notification_sent_at, trigger_id}
        )

      assert sent_at == last_sent_at
    end

    test "does not publish an event if within the notification embargo", %{
      trigger: %{id: trigger_id}
    } do
      Events.subscribe_to_kafka_trigger_updated()

      KafkaTriggers.notify_users_of_trigger_failure(trigger_id)

      refute_received(%Events.KafkaTriggerNotificationSent{})
    end
  end

  describe ".send_notification?/2" do
    setup do
      %{
        embargo_period: Lightning.Config.kafka_notification_embargo_seconds(),
        sending_at: DateTime.utc_now()
      }
    end

    test "true if we have never sent a notification", %{
      sending_at: sending_at
    } do
      last_sent_at = nil

      assert KafkaTriggers.send_notification?(sending_at, last_sent_at)
    end

    test "true if last notification was outside embargo period", %{
      embargo_period: embargo_period,
      sending_at: sending_at
    } do
      last_sent_at = DateTime.add(sending_at, -(embargo_period + 1), :second)

      assert KafkaTriggers.send_notification?(sending_at, last_sent_at)
    end

    test "false if last notification is on the border of the embargo period", %{
      embargo_period: embargo_period,
      sending_at: sending_at
    } do
      last_sent_at = DateTime.add(sending_at, embargo_period, :second)

      refute KafkaTriggers.send_notification?(sending_at, last_sent_at)
    end

    test "false if last notification is within the embargo period", %{
      embargo_period: embargo_period,
      sending_at: sending_at
    } do
      last_sent_at = DateTime.add(sending_at, -(embargo_period - 1), :second)

      refute KafkaTriggers.send_notification?(sending_at, last_sent_at)
    end
  end

  describe "failure_notification_tracking_key/1" do
    test "returns the keys used to track when a failure notificaton was sent" do
      trigger_id = Ecto.UUID.generate()

      key = KafkaTriggers.failure_notification_tracking_key(trigger_id)

      assert key == {:kafka_trigger_failure_notification_sent_at, trigger_id}
    end
  end

  defp child_spec(opts) do
    trigger = opts |> Keyword.get(:trigger)
    index = opts |> Keyword.get(:index)
    sasl = opts |> Keyword.get(:sasl, true)
    ssl = opts |> Keyword.get(:ssl, true)

    number_of_consumers =
      opts
      |> Keyword.get(
        :number_of_consumers,
        Lightning.Config.kafka_number_of_consumers()
      )

    number_of_processors =
      opts
      |> Keyword.get(
        :number_of_processors,
        Lightning.Config.kafka_number_of_processors()
      )

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
            number_of_consumers: number_of_consumers,
            number_of_processors: number_of_processors,
            offset_reset_policy: {:timestamp, offset_timestamp},
            rate_limit: KafkaTriggers.convert_rate_limit(),
            sasl: sasl_config(index, sasl),
            ssl: ssl,
            topics: ["topic-#{index}-1", "topic-#{index}-2"],
            trigger_id: trigger.id |> String.to_atom()
          ]
        ]
      }
    }
  end

  defp configuration(opts) do
    index = opts |> Keyword.get(:index, 1)
    sasl = opts |> Keyword.get(:sasl, true)
    ssl = opts |> Keyword.get(:ssl, true)

    password = if sasl, do: "secret-#{index}", else: nil
    sasl_type = if sasl, do: "plain", else: nil
    username = if sasl, do: "my-user-#{index}", else: nil

    initial_offset_reset_policy =
      opts |> Keyword.get(:initial_offset_reset_policy, "171524976732#{index}")

    %{
      connect_timeout: 30 + index,
      group_id: "lightning-#{index}",
      hosts: [["host-#{index}", "9092"], ["other-host-#{index}", "9093"]],
      initial_offset_reset_policy: initial_offset_reset_policy,
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

  defp build_trigger(initial_offset_reset) do
    kafka_configuration =
      configuration(initial_offset_reset_policy: initial_offset_reset)

    build(:trigger, type: :kafka, kafka_configuration: kafka_configuration)
  end

  defp setup_users_for_trigger(users_and_roles) do
    kafka_configuration = build(:triggers_kafka_configuration)

    project_users =
      users_and_roles
      |> Enum.map(fn {user, role} ->
        build(:project_user, user: user, role: role)
      end)

    project =
      insert(
        :project,
        project_users: project_users
      )

    workflow = insert(:workflow, project: project)

    insert(
      :trigger,
      type: :kafka,
      kafka_configuration: kafka_configuration,
      workflow: workflow
    )
  end
end
