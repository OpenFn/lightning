defmodule Lightning.KafkaTriggers.TriggerKafkaMessageRecordTest do
  use Lightning.DataCase

  alias Ecto.Changeset
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord, as: TKMR

  describe ".changeset" do
    setup do
      %{topic_partition_offset: "mytopic-3-1234", trigger: insert(:trigger)}
    end

    test "returns valid changeset if required params are provided", %{
      topic_partition_offset: topic_partition_offset,
      trigger: trigger
    } do
      trigger_id = trigger.id

      params = %{
        topic_partition_offset: topic_partition_offset,
        trigger_id: trigger_id
      }

      changes = TKMR.changeset(%TKMR{}, params)

      assert %Changeset {
                changes: %{
                  topic_partition_offset: ^topic_partition_offset,
                  trigger_id: ^trigger_id
                },
                valid?: true
             } = changes
    end

    test "requires topic_partition_offset", %{
      trigger: trigger
    } do
      trigger_id = trigger.id

      params = %{
        trigger_id: trigger_id
      }

      %{valid?: false, errors: errors} = TKMR.changeset(%TKMR{}, params)

      assert [
        topic_partition_offset: {
          "can't be blank",
          [validation: :required]
        }
      ] = errors
    end

    test "requires trigger_id", %{
      topic_partition_offset: topic_partition_offset
    } do

      params = %{
        topic_partition_offset: topic_partition_offset
      }

      %{valid?: false, errors: errors} = TKMR.changeset(%TKMR{}, params)

      assert [
        trigger_id: {
          "can't be blank",
          [validation: :required]
        }
      ] = errors
    end

    test "ensures that the combination of params is unique", %{
      topic_partition_offset: topic_partition_offset,
      trigger: trigger
    } do
      trigger_id = trigger.id

      params = %{
        topic_partition_offset: topic_partition_offset,
        trigger_id: trigger_id
      }

      assert {:ok, _} =
        TKMR.changeset(%TKMR{}, params) |> Repo.insert()

      assert {:error, %Changeset{errors: errors}} = 
        TKMR.changeset(%TKMR{}, params) |> Repo.insert()

      assert [
        trigger_id: {
          "has already been taken",
          [
            {:constraint, :unique},
            {:constraint_name, "trigger_kafka_message_records_pkey"}
          ]
        }
      ] = errors
    end
  end
end
