defmodule Lightning.Workflows.Trigger.KafkaConfigurationTest do
  use Lightning.DataCase, async: true

  alias Ecto.Changeset
  alias Lightning.Workflows.Trigger.KafkaConfiguration

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

    # TODO This is a bandaid for a live validation issue. Replace with a
    # better plan.
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

    # TODO Also test for empty
    test "returns empty string if hosts is nil" do
      changeset = KafkaConfiguration.changeset(%KafkaConfiguration{}, %{})

      %Changeset{
        changes: %{topics_string: topics_string}
      } = KafkaConfiguration.generate_topics_string(changeset)

      assert topics_string == ""
    end
  end

  describe "changeset/2" do
    setup do
      base_changes = %{
        group_id: "group_id",
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

      base_expectation = %{
        group_id: "group_id",
        hosts: [
          ["host1", "9092"],
          ["host2", "9093"]
        ],
        hosts_string: "host1:9092, host2:9093",
        initial_offset_reset_policy: "earliest",
        partition_timestamps: %{"1" => 1_717_174_749_123},
        password: "password",
        sasl: :plain,
        ssl: true,
        topics: ["foo", "bar"],
        topics_string: "foo, bar",
        username: "username"
      }

      %{
        base_changes: base_changes,
        base_expectation: base_expectation
      }
    end

    test "creates a valid changeset", %{
      base_changes: base_changes,
      base_expectation: base_expectation
    } do
      changeset =
        KafkaConfiguration.changeset(%KafkaConfiguration{}, base_changes)

      assert %Changeset{changes: changes, valid?: true} = changeset

      assert changes == base_expectation
    end

    test "allows hosts_string to override hosts", %{
      base_changes: base_changes,
      base_expectation: base_expectation
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes |> Map.merge(%{hosts_string: "host3:9094, host4:9095"})
        )

      assert %Changeset{changes: changes, valid?: true} = changeset

      expectation =
        base_expectation
        |> Map.merge(%{
          hosts: [
            ["host3", "9094"],
            ["host4", "9095"]
          ],
          hosts_string: "host3:9094, host4:9095"
        })

      assert changes == expectation
    end

    test "allows topics_string to override topics", %{
      base_changes: base_changes,
      base_expectation: base_expectation
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes |> Map.merge(%{topics_string: "biz, boz"})
        )

      assert %Changeset{changes: changes, valid?: true} = changeset

      expectation =
        base_expectation
        |> Map.merge(%{
          topics: ["biz", "boz"],
          topics_string: "biz, boz"
        })

      assert changes == expectation
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

    test "is invalid if hosts_string is not provided", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{hosts_string: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               hosts_string: {"can't be blank", [{:validation, :required}]}
             ]
    end

    test "is invalid if topics_string is not provided", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{topics_string: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               topics_string: {"can't be blank", [{:validation, :required}]}
             ]
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

    test "is invalid if group_id is not provided", %{
      base_changes: base_changes
    } do
      changeset =
        KafkaConfiguration.changeset(
          %KafkaConfiguration{},
          base_changes
          |> Map.merge(%{group_id: nil})
        )

      assert %Changeset{errors: errors, valid?: false} = changeset

      assert errors == [
               group_id: {"can't be blank", [{:validation, :required}]}
             ]
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

    test "does nothing if hosts_string is nil", %{
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

    test "clears hosts if hosts_string is an empty string", %{
      changeset: changeset
    } do
      changeset =
        changeset |> Changeset.put_change(:hosts_string, "")

      %Changeset{changes: %{hosts: hosts}} =
        changeset
        |> KafkaConfiguration.apply_hosts_string()

      assert hosts == []
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

    test "does nothing if topics_string is absent", %{
      changeset: changeset
    } do
      %Changeset{changes: %{topics: topics}} =
        changeset |> KafkaConfiguration.apply_topics_string()

      assert topics == ["foo", "bar"]
    end

    test "clears topics if topics_string is an empty string", %{
      changeset: changeset
    } do
      changeset =
        changeset
        |> Changeset.put_change(:topics_string, "")

      %Changeset{changes: %{topics: topics}} =
        changeset |> KafkaConfiguration.apply_topics_string()

      assert topics == []
    end
  end
end
