defmodule Lightning.Workflows.Triggers.KafkaConfigurationTest do
  use Lightning.DataCase, async: false

  alias Ecto.Changeset
  alias Lightning.Workflows.Triggers.KafkaConfiguration

  import Mock

  describe "generate_hosts_string/1" do
    test "adds hosts_string change to changeset" do
      changeset =
        KafkaConfiguration.changeset(%KafkaConfiguration{}, %{
          hosts: [
            ["host1", "9092"],
            ["host2", "9093"]
          ]
        })

      %Changeset{
        changes: %{hosts_string: hosts_string}
      } = KafkaConfiguration.generate_hosts_string(changeset)

      assert hosts_string == "host1:9092, host2:9093"
    end

    test "adds hosts_string change to changeset correctly for single host" do
      changeset =
        KafkaConfiguration.changeset(%KafkaConfiguration{}, %{
          hosts: [
            ["host1", "9092"]
          ]
        })

      %Changeset{
        changes: %{hosts_string: hosts_string}
      } = KafkaConfiguration.generate_hosts_string(changeset)

      assert hosts_string == "host1:9092"
    end

    test "returns empty string if hosts is nil" do
      changeset = KafkaConfiguration.changeset(%KafkaConfiguration{}, %{})

      %Changeset{
        changes: %{hosts_string: hosts_string}
      } = KafkaConfiguration.generate_hosts_string(changeset)

      assert hosts_string == ""
    end

    test "returns empty string if hosts is an empty list" do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          %{
            hosts: []
          }
        )

      %Changeset{
        changes: %{hosts_string: hosts_string}
      } = KafkaConfiguration.generate_hosts_string(changeset)

      assert hosts_string == ""
    end

    test "returns_host as-is if not properly formed" do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          %{
            hosts: [
              ["host1"],
              ["host2", "9093"]
            ]
          }
        )

      %Changeset{
        changes: %{hosts_string: hosts_string}
      } = KafkaConfiguration.generate_hosts_string(changeset)

      assert hosts_string == "host1, host2:9093"
    end
  end

  describe "generate_topics_string/1" do
    test "adds hosts_string change to changeset" do
      changeset =
        KafkaConfiguration.changeset(%KafkaConfiguration{}, %{
          topics: ["foo", "bar"]
        })

      %Changeset{
        changes: %{topics_string: topics_string}
      } = KafkaConfiguration.generate_topics_string(changeset)

      assert topics_string == "foo, bar"
    end

    test "adds topics_string change to changeset correctly for single topic" do
      changeset =
        KafkaConfiguration.changeset(%KafkaConfiguration{}, %{
          topics: ["foo"]
        })

      %Changeset{
        changes: %{topics_string: topics_string}
      } = KafkaConfiguration.generate_topics_string(changeset)

      assert topics_string == "foo"
    end

    test "returns empty string if topics is nil" do
      changeset = KafkaConfiguration.changeset(%KafkaConfiguration{}, %{})

      %Changeset{
        changes: %{topics_string: topics_string}
      } = KafkaConfiguration.generate_topics_string(changeset)

      assert topics_string == ""
    end

    test "returns empty string if topics is empty" do
      changeset =
        KafkaConfiguration.changeset(%KafkaConfiguration{topics: []}, %{})

      %Changeset{
        changes: %{topics_string: topics_string}
      } = KafkaConfiguration.generate_topics_string(changeset)

      assert topics_string == ""
    end
  end

  describe "changeset/2" do
    setup do
      base_changes = %{
        connect_timeout: 7,
        hosts: [
          ["host1", "9092"],
          ["host2", "9093"]
        ],
        hosts_string: "host1:9092, host2:9093",
        initial_offset_reset_policy: "earliest",
        partition_timestamps: %{"1" => 1_717_174_749_123},
        password: "password",
        reset_request: %{
          requested_at: ~U[2024-09-11 12:14:11.019240Z],
          reset_to: 1_723_633_665_366
        },
        sasl: "plain",
        ssl: true,
        topics: ["foo", "bar"],
        topics_string: "foo, bar",
        username: "username"
      }

      base_expectation = %{
        connect_timeout: 7,
        hosts: [
          ["host1", "9092"],
          ["host2", "9093"]
        ],
        hosts_string: "host1:9092, host2:9093",
        initial_offset_reset_policy: "earliest",
        partition_timestamps: %{"1" => 1_717_174_749_123},
        password: "password",
        reset_request: %{
          requested_at: ~U[2024-09-11 12:14:11.019240Z],
          reset_to: 1_723_633_665_366
        },
        sasl: :plain,
        ssl: true,
        topics: ["foo", "bar"],
        topics_string: "foo, bar",
        username: "username"
      }

      %{
        base_changes: base_changes,
        base_expectation: base_expectation,
        changes_sans_group_id: base_expectation
      }
    end

    test "creates a valid changeset", %{
      base_changes: base_changes,
      changes_sans_group_id: changes_sans_group_id
    } do
      changeset =
        KafkaConfiguration.changeset(%KafkaConfiguration{}, base_changes)

      partial_group_id_pattern = ~r/^lightning-[[:xdigit:]]{8}/

      assert %Changeset{changes: changes, valid?: true} = changeset
      assert changes |> Map.delete(:group_id) == changes_sans_group_id
      assert changes.group_id |> String.match?(partial_group_id_pattern)
    end

    test "allows hosts_string to override hosts", %{
      base_changes: base_changes,
      changes_sans_group_id: changes_sans_group_id
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes |> Map.merge(%{hosts_string: "host3:9094, host4:9095"})
        )

      assert %Changeset{changes: changes, valid?: true} = changeset

      expectation =
        changes_sans_group_id
        |> Map.merge(%{
          hosts: [
            ["host3", "9094"],
            ["host4", "9095"]
          ],
          hosts_string: "host3:9094, host4:9095"
        })

      assert changes |> Map.delete(:group_id) == expectation
    end

    test "allows topics_string to override topics", %{
      base_changes: base_changes,
      changes_sans_group_id: changes_sans_group_id
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes |> Map.merge(%{topics_string: "biz, boz"})
        )

      assert %Changeset{changes: changes, valid?: true} = changeset

      expectation =
        changes_sans_group_id
        |> Map.merge(%{
          topics: ["biz", "boz"],
          topics_string: "biz, boz"
        })

      assert changes |> Map.delete(:group_id) == expectation
    end

    test "is invalid if sasl selected but no username", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{sasl: "plain", username: nil, password: "x"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               username: {"Required if SASL is selected", []}
             ]
    end

    test "is invalid if sasl selected but no password", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{sasl: "plain", username: "x", password: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               password: {"Required if SASL is selected", []}
             ]
    end

    test "is invalid if sasl selected but no username or password", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{sasl: "plain", username: nil, password: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      password_error = errors |> Keyword.get(:password, nil)
      assert password_error == {"Required if SASL is selected", []}

      username_error = errors |> Keyword.get(:username, nil)
      assert username_error == {"Required if SASL is selected", []}
    end

    test "is invalid if no sasl but username", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{sasl: nil, username: "x", password: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               username: {"Requires SASL to be selected", []}
             ]
    end

    test "is invalid if no sasl but password", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{sasl: nil, username: nil, password: "x"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               password: {"Requires SASL to be selected", []}
             ]
    end

    test "is invalid if no sasl but username and password", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{sasl: nil, username: "x", password: "x"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      password_error = errors |> Keyword.get(:password, nil)
      assert password_error == {"Requires SASL to be selected", []}

      username_error = errors |> Keyword.get(:username, nil)
      assert username_error == {"Requires SASL to be selected", []}
    end

    test "is valid if hosts_string is not provided but hosts is set", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{hosts_string: nil})
        )

      assert %Changeset{valid?: true} = changeset
    end

    test "is invalid if invalid hosts_string is provided", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{hosts_string: "oops"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               hosts_string: {
                 "Must be specified in the format `host:port, host:port`",
                 []
               }
             ]
    end

    test "is valid if topics_string is not provided but topics is set", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{topics_string: nil})
        )

      assert %Changeset{valid?: true} = changeset
    end

    test "is invalid if invalid topics_string is provided", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{topics_string: ","})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               topics_string: {
                 "Must be specified in the format `topic_1, topic_2`",
                 []
               }
             ]
    end

    test "is invalid if hosts is nil", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{hosts: nil, hosts_string: nil})
        )

      assert %Changeset{
               errors: [{:hosts, errors} | _other_errors],
               valid?: false
             } = changeset

      expected_hosts_errors = {
        "can't be blank",
        [{:validation, :required}]
      }

      assert errors == expected_hosts_errors
    end

    test "is invalid if hosts is an empty array", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{hosts: [], hosts_string: nil})
        )

      assert %Changeset{
               errors: [{:hosts, errors} | _other_errors],
               valid?: false
             } = changeset

      expected_hosts_errors = {
        "should have at least %{count} item(s)",
        [{:count, 1}, {:validation, :length}, {:kind, :min}, {:type, :list}]
      }

      assert errors == expected_hosts_errors
    end

    test "is invalid if topics is nil", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{topics: nil, topics_string: nil})
        )

      assert %Changeset{
               errors: [{:topics, errors} | _other_errors],
               valid?: false
             } = changeset

      expected_topics_errors = {
        "can't be blank",
        [{:validation, :required}]
      }

      assert errors == expected_topics_errors
    end

    test "is invalid if topics is an empty array", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{topics: [], topics_string: nil})
        )

      assert %Changeset{
               errors: [{:topics, errors} | _other_errors],
               valid?: false
             } = changeset

      expected_topics_errors = {
        "should have at least %{count} item(s)",
        [{:count, 1}, {:validation, :length}, {:kind, :min}, {:type, :list}]
      }

      assert errors == expected_topics_errors
    end

    test "is invalid if initial_offset_reset_policy is not provided", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{initial_offset_reset_policy: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               initial_offset_reset_policy: {
                 "can't be blank",
                 [{:validation, :required}]
               }
             ]
    end

    test "invalid if initial_offset_reset_policy is not an expected value", %{
      base_changes: base_changes
    } do
      error_message =
        "must be `earliest`, `latest` or timestamp with millisecond precision" <>
          " (e.g. `1720428955123`)"

      # String that is neither earliest nor latest and cannto be converted to a
      # number
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{initial_offset_reset_policy: "whenever"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [initial_offset_reset_policy: {error_message, []}]
    end

    test "is invalid if connect_timeout is not provided", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{connect_timeout: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               connect_timeout: {
                 "can't be blank",
                 [{:validation, :required}]
               }
             ]
    end

    test "is invalid if connect_timeout is not an integer", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{connect_timeout: 1.5})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               connect_timeout: {
                 "is invalid",
                 [
                   {:type, :integer},
                   {:validation, :cast}
                 ]
               }
             ]
    end

    test "is invalid if connect_timeout is negative", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{connect_timeout: -1})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               connect_timeout: {
                 "must be greater than %{number}",
                 [
                   {:validation, :number},
                   {:kind, :greater_than},
                   {:number, 0}
                 ]
               }
             ]
    end

    test "is invalid if connect_timeout is zero", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{connect_timeout: 0})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               connect_timeout: {
                 "must be greater than %{number}",
                 [
                   {:validation, :number},
                   {:kind, :greater_than},
                   {:number, 0}
                 ]
               }
             ]
    end

    test "is invalid if the `reset_request` contains invalid data", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{reset_request: %{}})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert [reset_request: {_message, []}] = errors
    end
  end

  describe ".apply_hosts_string/2" do
    setup do
      changeset =
        Changeset.change(
          %KafkaConfiguration{},
          hosts: [
            ["host1", "9092"],
            ["host2", "9093"]
          ]
        )

      %{changeset: changeset}
    end

    test "replaces the hosts with hosts from the hosts_string", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:hosts_string, "host3:9094, host4:9095")

      %Changeset{changes: %{hosts: hosts}} =
        changeset
        |> KafkaConfiguration.apply_hosts_string()

      assert hosts == [
               ["host3", "9094"],
               ["host4", "9095"]
             ]
    end

    test "removes whitespace from the hosts_string entries", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:hosts_string, " host3 : 9094 , host4:9095 ")

      %Changeset{changes: %{hosts: hosts}} =
        changeset
        |> KafkaConfiguration.apply_hosts_string()

      assert hosts == [
               ["host3", "9094"],
               ["host4", "9095"]
             ]
    end

    test "does nothing if hosts_string is nil but hosts is populated", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:hosts_string, nil)

      %Changeset{changes: %{hosts: hosts}} =
        changeset
        |> KafkaConfiguration.apply_hosts_string()

      assert hosts == [
               ["host1", "9092"],
               ["host2", "9093"]
             ]
    end

    test "sets an error if hosts_string is nil and hosts is nil", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:hosts, nil)
        |> Changeset.put_change(:hosts_string, nil)

      changeset =
        changeset
        |> KafkaConfiguration.apply_hosts_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               hosts_string: {
                 "Must be specified in the format `host:port, host:port`",
                 []
               }
             ]
    end

    test "does nothing if hosts_string is nil but hosts is empty", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:hosts, [])
        |> Changeset.put_change(:hosts_string, nil)

      changeset =
        changeset
        |> KafkaConfiguration.apply_hosts_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               hosts_string: {
                 "Must be specified in the format `host:port, host:port`",
                 []
               }
             ]
    end

    test "does nothing if hosts_string is absent", %{
      changeset: changeset
    } do
      %Changeset{changes: %{hosts: hosts}} =
        changeset
        |> KafkaConfiguration.apply_hosts_string()

      assert hosts == [
               ["host1", "9092"],
               ["host2", "9093"]
             ]
    end

    test "sets an error if hosts_string is an empty string", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:hosts_string, "")
        |> KafkaConfiguration.apply_hosts_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               hosts_string: {
                 "Must be specified in the format `host:port, host:port`",
                 []
               }
             ]
    end

    test "sets an error if the host/port couplets are incorrect", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:hosts_string, "host3, host4:9095")
        |> KafkaConfiguration.apply_hosts_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               hosts_string: {
                 "Must be specified in the format `host:port, host:port`",
                 []
               }
             ]
    end
  end

  describe ".apply_topics_string/2" do
    setup do
      changeset =
        Changeset.change(
          %KafkaConfiguration{},
          topics: ["foo", "bar"]
        )

      %{changeset: changeset}
    end

    test "replaces the topics with topics from topics_string", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics_string, "biz,boz")

      %Changeset{changes: %{topics: topics}} =
        changeset |> KafkaConfiguration.apply_topics_string()

      assert topics == ["biz", "boz"]
    end

    test "removes whitespace from the topics_string entries", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics_string, " biz , boz ")

      %Changeset{changes: %{topics: topics}} =
        changeset |> KafkaConfiguration.apply_topics_string()

      assert topics == ["biz", "boz"]
    end

    test "does nothing if topics_string is nil", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics_string, nil)

      %Changeset{changes: %{topics: topics}} =
        changeset |> KafkaConfiguration.apply_topics_string()

      assert topics == ["foo", "bar"]
    end

    test "sets an error if topics_string is nil and topics is nil", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics, nil)
        |> Changeset.put_change(:topics_string, nil)
        |> KafkaConfiguration.apply_topics_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               topics_string: {
                 "Must be specified in the format `topic_1, topic_2`",
                 []
               }
             ]
    end

    test "sets an error if topics_string is nil and topics is empty", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics, [])
        |> Changeset.put_change(:topics_string, nil)
        |> KafkaConfiguration.apply_topics_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               topics_string: {
                 "Must be specified in the format `topic_1, topic_2`",
                 []
               }
             ]
    end

    test "does nothing if topics_string is absent", %{
      changeset: changeset
    } do
      %Changeset{changes: %{topics: topics}} =
        changeset |> KafkaConfiguration.apply_topics_string()

      assert topics == ["foo", "bar"]
    end

    test "sets an error if topics_string is an empty string", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics_string, "")
        |> KafkaConfiguration.apply_topics_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               topics_string: {
                 "Must be specified in the format `topic_1, topic_2`",
                 []
               }
             ]
    end

    test "sets an error if topics_string parses to an empty array", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics_string, " , ")
        |> KafkaConfiguration.apply_topics_string()

      assert %{errors: errors, valid?: false} = changeset

      assert errors == [
               topics_string: {
                 "Must be specified in the format `topic_1, topic_2`",
                 []
               }
             ]
    end
  end

  describe ".set_group_id_if_required/1" do
    test "adds a generated group_id to the changeset" do
      with_mock Ecto.UUID,
        generate: fn -> "a-b-c-d" end do
        changeset =
          Changeset.change(%KafkaConfiguration{}, %{})
          |> KafkaConfiguration.set_group_id_if_required()

        assert %Changeset{changes: %{group_id: "lightning-a-b-c-d"}} = changeset
      end
    end

    test "does not add a change if the struct already has a group_id" do
      changeset =
        %KafkaConfiguration{group_id: "foo"}
        |> Changeset.change(%{})
        |> KafkaConfiguration.set_group_id_if_required()

      %Changeset{changes: changes} = changeset

      assert changes == %{}
    end

    test "clears any existing group_id changes" do
      changeset =
        %KafkaConfiguration{group_id: "foo"}
        |> Changeset.change(%{group_id: "bar"})
        |> KafkaConfiguration.set_group_id_if_required()

      %Changeset{changes: changes} = changeset

      assert changes == %{}

      with_mock Ecto.UUID,
        generate: fn -> "a-b-c-d" end do
        changeset =
          %KafkaConfiguration{}
          |> Changeset.change(%{group_id: "foo"})
          |> KafkaConfiguration.set_group_id_if_required()

        assert %Changeset{changes: %{group_id: "lightning-a-b-c-d"}} = changeset
      end
    end
  end

  describe ".partitions_changeset/3" do
    setup do
      %{partition: 7, timestamp: 124}
    end

    test "adds data for partition if there is no partition data", %{
      partition: partition,
      timestamp: timestamp
    } do
      config =
        build(:triggers_kafka_configuration, partition_timestamps: %{})

      expected_timestamps = %{
        "#{partition}" => timestamp
      }

      changeset =
        config
        |> KafkaConfiguration.partitions_changeset(partition, timestamp)

      assert %Changeset{changes: changes, valid?: true} = changeset

      assert %{partition_timestamps: ^expected_timestamps} = changes
    end

    test "adds data for partition if partition is new but there is data", %{
      partition: partition,
      timestamp: timestamp
    } do
      config =
        build(:triggers_kafka_configuration, partition_timestamps: %{"3" => 123})

      expected_timestamps = %{
        "3" => 123,
        "#{partition}" => timestamp
      }

      changeset =
        config
        |> KafkaConfiguration.partitions_changeset(partition, timestamp)

      assert %Changeset{changes: changes, valid?: true} = changeset

      assert %{partition_timestamps: ^expected_timestamps} = changes
    end

    test "does not update partition data if persisted timestamp is newer", %{
      partition: partition,
      timestamp: timestamp
    } do
      config =
        build(
          :triggers_kafka_configuration,
          partition_timestamps: %{
            "3" => 123,
            "#{partition}" => timestamp + 1
          }
        )

      changeset =
        config
        |> KafkaConfiguration.partitions_changeset(partition, timestamp)

      assert changeset |> Changeset.get_change(:partition_timestamps) == nil
    end

    test "updates persisted partition data if persisted timestamp is older", %{
      partition: partition,
      timestamp: timestamp
    } do
      config =
        build(
          :triggers_kafka_configuration,
          partition_timestamps: %{
            "3" => 123,
            "#{partition}" => timestamp - 1
          }
        )

      expected_timestamps = %{
        "3" => 123,
        "#{partition}" => timestamp
      }

      changeset =
        config
        |> KafkaConfiguration.partitions_changeset(partition, timestamp)

      assert %Changeset{changes: changes, valid?: true} = changeset

      assert %{partition_timestamps: ^expected_timestamps} = changes
    end
  end

  describe ".validate_initial_offset_reset_policy/1" do
    setup do
      base_changes = %{
        connect_timeout: 7,
        hosts: [
          ["host1", "9092"],
          ["host2", "9093"]
        ],
        hosts_string: "host1:9092, host2:9093",
        initial_offset_reset_policy: "earliest",
        partition_timestamps: %{"1" => 1_717_174_749_123},
        password: "password",
        sasl: "plain",
        ssl: true,
        topics: ["foo", "bar"],
        topics_string: "foo, bar",
        username: "username"
      }

      error_message =
        "must be `earliest`, `latest` or timestamp with millisecond precision" <>
          " (e.g. `1720428955123`)"

      %{
        base_changes: base_changes,
        error_message: error_message
      }
    end

    test "changeset is valid if initial_offset_reset_policy is `earliest`", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
        )
        |> Changeset.put_change(:initial_offset_reset_policy, "earliest")
        |> KafkaConfiguration.validate_initial_offset_reset_policy()

      assert %Changeset{valid?: true} = changeset
    end

    test "changeset is valid if it is `latest`", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
        )
        |> Changeset.put_change(:initial_offset_reset_policy, "latest")
        |> KafkaConfiguration.validate_initial_offset_reset_policy()

      assert %Changeset{valid?: true} = changeset
    end

    test "changeset is valid if it is a timestamp", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
        )
        |> Changeset.put_change(:initial_offset_reset_policy, "1720428955123")
        |> KafkaConfiguration.validate_initial_offset_reset_policy()

      assert %Changeset{valid?: true} = changeset
    end

    test "trims any whitespace off the initial_offset_reset_policy", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
        )
        |> Changeset.put_change(:initial_offset_reset_policy, " earliest ")
        |> KafkaConfiguration.validate_initial_offset_reset_policy()

      assert %Changeset{valid?: true} = changeset

      assert changeset
             |> Changeset.get_change(:initial_offset_reset_policy) == "earliest"

      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
        )
        |> Changeset.put_change(:initial_offset_reset_policy, " 1720428955123 ")
        |> KafkaConfiguration.validate_initial_offset_reset_policy()

      assert %Changeset{valid?: true} = changeset

      assert changeset
             |> Changeset.get_change(:initial_offset_reset_policy) ==
               "1720428955123"
    end

    test "changeset is valid if there is no change", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
        )
        |> Changeset.put_change(:initial_offset_reset_policy, nil)
        |> KafkaConfiguration.validate_initial_offset_reset_policy()

      assert %Changeset{valid?: true} = changeset
    end

    test "changeset invalid if other non-numerical string", %{
      base_changes: base_changes,
      error_message: error_message
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{initial_offset_reset_policy: "whenever"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [initial_offset_reset_policy: {error_message, []}]
    end

    test "changeset invalid if number but not timestamp", %{
      base_changes: base_changes,
      error_message: error_message
    } do
      # One digit too short
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{initial_offset_reset_policy: "172000930622"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [initial_offset_reset_policy: {error_message, []}]

      # One digit too long
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{initial_offset_reset_policy: "17200093062219"})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [initial_offset_reset_policy: {error_message, []}]
    end
  end

  describe ".sasl_types/0" do
    test "returns acceptable sasl_types" do
      expected_types = ["plain", "scram_sha_256", "scram_sha_512"]

      assert KafkaConfiguration.sasl_types() == expected_types
    end
  end

  describe ".validate_reset_request/1" do
    setup do
      base_changes = %{
        reset_request: %{
          requested_at: ~U[2024-09-11 12:14:11.019240Z],
          reset_to: 1_723_633_665_366
        }
      }

      base_changeset =
        change(%KafkaConfiguration{}, base_changes)

      error_message =
        "must be a map with both `requested_at` and `reset_to` elements " <>
          "set to nil or `requested_at` a valid DateTime and " <>
          "`reset_to` a positive integer"

      %{
        error_message: error_message,
        base_changeset: base_changeset
      }
    end

    test "is valid if reset_to is a timestamp and requested_at is a datetime", %{
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{valid?: true} = changeset
    end

    test "is valid if both elements are set to nil" do
      config =
        %KafkaConfiguration{
          reset_request: %{
            requested_at: ~U[2024-09-11 12:14:11.019240Z],
            reset_to: 1_723_633_665_366
          }
        }

      changeset =
        config
        |> Changeset.change(%{
          reset_request: %{
            requested_at: nil,
            reset_to: nil
          }
        })
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{valid?: true} = changeset
    end

    test "is valid if there are no changes to the reset_request", %{
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.delete_change(:reset_request)
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{valid?: true} = changeset
    end

    test "is invalid if requested_at is absent", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(:reset_request, %{reset_to: 1_723_633_665_366})
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end

    test "is invalid if requested_at is nil", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(
          :reset_request,
          %{requested_at: nil, reset_to: 1_723_633_665_366}
        )
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end

    test "is invalid if reset_to is absent", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(
          :reset_request,
          %{requested_at: ~U[2024-09-11 12:14:11.019240Z]}
        )
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end

    test "is invalid if reset_to is nil", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(
          :reset_request,
          %{requested_at: ~U[2024-09-11 12:14:11.019240Z], reset_to: nil}
        )
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end

    test "is invalid if requested_at is not a datetime", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(
          :reset_request,
          %{requested_at: "foo", reset_to: 1_723_633_665_366}
        )
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end

    test "is invalid if reset_to is not an integer", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(
          :reset_request,
          %{
            requested_at: ~U[2024-09-11 12:14:11.019240Z],
            reset_to: "foo"
          }
        )
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end

    test "is invalid if reset_to is negative", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(
          :reset_request,
          %{
            requested_at: ~U[2024-09-11 12:14:11.019240Z],
            reset_to: -1
          }
        )
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end

    test "is invalid if reset_request is an empty map", %{
      error_message: error_message,
      base_changeset: base_changeset
    } do
      changeset =
        base_changeset
        |> Changeset.put_change(:reset_request, %{})
        |> KafkaConfiguration.validate_reset_request()

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [reset_request: {error_message, []}]
    end
  end
end
