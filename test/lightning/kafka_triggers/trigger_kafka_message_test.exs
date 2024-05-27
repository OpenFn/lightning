defmodule Lightning.KafkaTriggers.TriggerKafkaMessageTest do
  use Lightning.DataCase

  alias Ecto.Changeset
  alias Lightning.KafkaTriggers.TriggerKafkaMessage

  describe ".changeset/2" do
    setup do
      %{
        data: "xxxxx",
        key: "my_key",
        message_timestamp: 1_715_164_718_283,
        metadata: %{meta: :data},
        topic: "my_topic",
        trigger: insert(:trigger, type: :kafka),
        work_order: insert(:workorder)
      }
    end

    test "returns a valid changeset", %{
      data: data,
      key: key,
      message_timestamp: message_timestamp,
      metadata: metadata,
      topic: topic,
      trigger: trigger,
      work_order: work_order
    } do
      trigger_id = trigger.id
      work_order_id = work_order.id

      attributes = %{
        data: data,
        key: key,
        message_timestamp: message_timestamp,
        metadata: metadata,
        topic: topic,
        trigger_id: trigger.id,
        work_order_id: work_order.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %Changeset{changes: changes, valid?: true} = changeset

      assert %{
               data: ^data,
               key: ^key,
               message_timestamp: ^message_timestamp,
               metadata: ^metadata,
               topic: ^topic,
               trigger_id: ^trigger_id,
               work_order_id: ^work_order_id
             } = changes
    end

    test "is invalid if data is not provided", %{
      key: key,
      message_timestamp: message_timestamp,
      metadata: metadata,
      topic: topic,
      trigger: trigger,
      work_order: work_order
    } do
      attributes = %{
        key: key,
        message_timestamp: message_timestamp,
        metadata: metadata,
        topic: topic,
        trigger_id: trigger.id,
        work_order_id: work_order.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %{valid?: false, errors: errors} = changeset

      assert [
               {:data, {"can't be blank", [validation: :required]}}
             ] = errors
    end

    test "is valid if key is not provided", %{
      data: data,
      message_timestamp: message_timestamp,
      metadata: metadata,
      topic: topic,
      trigger: trigger,
      work_order: work_order
    } do
      attributes = %{
        data: data,
        message_timestamp: message_timestamp,
        metadata: metadata,
        topic: topic,
        trigger_id: trigger.id,
        work_order_id: work_order.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %{valid?: true} = changeset
    end

    test "is invalid if message_timestamp is not provided", %{
      data: data,
      key: key,
      metadata: metadata,
      topic: topic,
      trigger: trigger,
      work_order: work_order
    } do
      attributes = %{
        data: data,
        key: key,
        metadata: metadata,
        topic: topic,
        trigger_id: trigger.id,
        work_order_id: work_order.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %{valid?: false, errors: errors} = changeset

      assert [
               {:message_timestamp, {"can't be blank", [validation: :required]}}
             ] = errors
    end

    test "is invalid if metadata is not provided", %{
      data: data,
      key: key,
      message_timestamp: message_timestamp,
      topic: topic,
      trigger: trigger,
      work_order: work_order
    } do
      attributes = %{
        data: data,
        key: key,
        message_timestamp: message_timestamp,
        topic: topic,
        trigger_id: trigger.id,
        work_order_id: work_order.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %{valid?: false, errors: errors} = changeset

      assert [
               {:metadata, {"can't be blank", [validation: :required]}}
             ] = errors
    end

    test "is invalid if topic is not provided", %{
      data: data,
      key: key,
      message_timestamp: message_timestamp,
      metadata: metadata,
      trigger: trigger,
      work_order: work_order
    } do
      attributes = %{
        data: data,
        key: key,
        message_timestamp: message_timestamp,
        metadata: metadata,
        trigger_id: trigger.id,
        work_order_id: work_order.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %{valid?: false, errors: errors} = changeset

      assert [
               {:topic, {"can't be blank", [validation: :required]}}
             ] = errors
    end

    test "is invalid if trigger_id is not provided", %{
      data: data,
      key: key,
      message_timestamp: message_timestamp,
      metadata: metadata,
      topic: topic,
      work_order: work_order
    } do
      attributes = %{
        data: data,
        key: key,
        message_timestamp: message_timestamp,
        metadata: metadata,
        topic: topic,
        work_order_id: work_order.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %{valid?: false, errors: errors} = changeset

      assert [
               {:trigger_id, {"can't be blank", [validation: :required]}}
             ] = errors
    end

    test "is valid if a worker_order_id is not provided", %{
      data: data,
      key: key,
      message_timestamp: message_timestamp,
      metadata: metadata,
      topic: topic,
      trigger: trigger
    } do
      attributes = %{
        data: data,
        key: key,
        message_timestamp: message_timestamp,
        metadata: metadata,
        topic: topic,
        trigger_id: trigger.id
      }

      changeset =
        %TriggerKafkaMessage{}
        |> TriggerKafkaMessage.changeset(attributes)

      assert %Changeset{valid?: true} = changeset
    end
  end
end