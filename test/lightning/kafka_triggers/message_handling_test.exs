defmodule Lightning.KafkaTriggers.MessageHandlingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  require Lightning.Run

  alias Ecto.Multi
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Invocation
  alias Lightning.KafkaTriggers.MessageHandling
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.WorkOrder

  describe ".persist_message/3" do
    setup do
      message = build_broadway_message()

      message_with_headers =
        build_broadway_message(
          headers: [
            {"foo_header", "foo_value"},
            {"bar_header", "bar_value"},
            {"foo_header", "other_foo_value"}
          ]
        )

      %{workflow: workflow} = trigger = insert(:trigger, type: :kafka)

      workflow |> with_snapshot()

      record_changeset =
        TriggerKafkaMessageRecord.changeset(
          %TriggerKafkaMessageRecord{},
          %{topic_partition_offset: "foo-bar-baz", trigger_id: trigger.id}
        )

      multi =
        Multi.new()
        |> Multi.insert(:record, record_changeset)

      %{
        message: message,
        message_with_headers: message_with_headers,
        multi: multi,
        trigger: trigger
      }
    end

    test "creates the WorkOrder for a message without headers", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger

      MessageHandling.persist_message(multi, trigger.id, message)

      created_workorder =
        WorkOrder
        |> Repo.one()
        |> Repo.preload([
          :trigger,
          :workflow,
          dataclip: Invocation.Query.dataclip_with_body()
        ])

      assert created_workorder.trigger_id == trigger.id
      assert created_workorder.workflow_id == workflow.id
      assert created_workorder.state == :pending

      %{dataclip: dataclip} = created_workorder
      assert dataclip.body["data"] == %{"interesting" => "stuff"}
      assert dataclip.body["request"] == message.metadata |> persisted_metadata()
      assert dataclip.type == :kafka
      assert dataclip.project_id == workflow.project_id
    end

    test "creates the WorkOrder for a message with headers", %{
      message_with_headers: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      MessageHandling.persist_message(multi, trigger.id, message)

      created_workorder =
        WorkOrder
        |> Repo.one()
        |> Repo.preload([
          :trigger,
          :workflow,
          dataclip: Invocation.Query.dataclip_with_body()
        ])

      assert created_workorder.trigger_id == trigger.id
      assert created_workorder.workflow_id == workflow.id
      assert created_workorder.state == :pending

      %{dataclip: dataclip} = created_workorder
      assert dataclip.body["data"] == %{"interesting" => "stuff"}
      assert dataclip.body["request"] == message.metadata |> persisted_metadata()
      assert dataclip.type == :kafka
      assert dataclip.project_id == workflow.project_id
    end

    test "executes any other instructions in the multi", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      MessageHandling.persist_message(multi, trigger.id, message)

      assert TriggerKafkaMessageRecord
             |> Repo.get_by(trigger_id: trigger.id) != nil
    end

    test "returns the results of the insertion", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      assert {:ok, work_order} =
               MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.get(work_order.id) != nil
    end

    test "creates a rejected work order if run creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :too_many_runs,
         %Message{text: "Too many runs in the last minute"}}
      end)

      MessageHandling.persist_message(multi, trigger.id, message)

      created_workorder =
        WorkOrder
        |> Repo.one()
        |> Repo.preload([
          :trigger,
          :workflow,
          dataclip: Invocation.Query.dataclip_with_body()
        ])

      assert created_workorder.trigger_id == trigger.id
      assert created_workorder.workflow_id == workflow.id
      assert created_workorder.state == :rejected

      %{dataclip: dataclip} = created_workorder
      assert dataclip.body["data"] == %{"interesting" => "stuff"}
      assert dataclip.body["request"] == message.metadata |> stringify_keys()
      assert dataclip.type == :kafka
      assert dataclip.project_id == workflow.project_id
    end

    test "returns results of the insertion if run creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :too_many_runs,
         %Message{text: "Too many runs in the last minute"}}
      end)

      assert {:ok, work_order} =
               MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.get(work_order.id) != nil
    end

    test "does not create a workorder if workorder creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.all() == []
    end

    test "returns an error response if workorder creation is constrained", %{
      message: message,
      multi: multi,
      trigger: trigger
    } do
      %{workflow: workflow} = trigger
      project_id = workflow.project_id

      action = %Action{type: :new_run}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :runs_hard_limit,
         %Lightning.Extensions.Message{text: "Runs limit exceeded"}}
      end)

      assert MessageHandling.persist_message(multi, trigger.id, message) ==
               {:error, :work_order_creation_blocked, "Runs limit exceeded"}
    end

    test "does not create a work order if data is not valid JSON", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "not a JSON object")

      MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.all() == []
    end

    test "returns an error if data is not valid JSON", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "not a JSON object")

      assert MessageHandling.persist_message(multi, trigger.id, message) ==
               {:error, :data_is_not_json}
    end

    test "does not create a work order if data is not a map", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "\"not a JSON object\"")

      MessageHandling.persist_message(multi, trigger.id, message)

      assert WorkOrder |> Repo.all() == []
    end

    test "returns an error indicating that the data can not be parsed", %{
      multi: multi,
      trigger: trigger
    } do
      message = build_broadway_message(data_as_json: "\"not a JSON object\"")

      assert MessageHandling.persist_message(multi, trigger.id, message) ==
               {:error, :data_is_not_json_object}
    end

    defp build_broadway_message(opts \\ []) do
      data =
        Keyword.get(
          opts,
          :data_as_json,
          %{interesting: "stuff"} |> Jason.encode!()
        )

      headers = Keyword.get(opts, :headers, [])
      key = Keyword.get(opts, :key, "abc_123_def")
      offset = Keyword.get(opts, :offset, 11)

      %Broadway.Message{
        data: data,
        metadata: %{
          offset: offset,
          partition: 2,
          key: key,
          headers: headers,
          ts: 1_715_164_718_283,
          topic: "bar_topic"
        },
        acknowledger: nil,
        batcher: :default,
        batch_key: {"bar_topic", 2},
        batch_mode: :bulk,
        status: :ok
      }
    end

    defp persisted_metadata(metadata) do
      metadata
      |> Enum.reduce(%{}, fn {key, val}, acc ->
        persisted_value =
          key
          |> case do
            :headers ->
              val |> convert_list_of_tuples_to_list_of_lists()

            _ ->
              val
          end

        acc |> Map.put(Atom.to_string(key), persisted_value)
      end)
    end

    defp convert_list_of_tuples_to_list_of_lists(list) do
      list |> Enum.map(fn {key, val} -> [key, val] end)
    end
  end

  describe ".convert_headers_for_serialisation/1" do
    test "converts headers in a metadata map to a list of lists" do
      metadata = %{
        headers: [
          {"foo_header", "foo_value"},
          {"bar_header", "bar_value"}
        ],
        offset: 999,
        topic: "bar"
      }

      expected_metadata = %{
        headers: [
          ["foo_header", "foo_value"],
          ["bar_header", "bar_value"]
        ],
        offset: 999,
        topic: "bar"
      }

      returned_metadata =
        MessageHandling.convert_headers_for_serialisation(metadata)

      assert returned_metadata == expected_metadata
    end

    test "passes headers through unchanged if aready a list of lists" do
      metadata = %{
        headers: [
          ["foo_header", "foo_value"],
          ["bar_header", "bar_value"]
        ],
        offset: 999,
        topic: "bar"
      }

      returned_metadata =
        MessageHandling.convert_headers_for_serialisation(metadata)

      assert returned_metadata == metadata
    end
  end

  # Put this in a helper
  defp stringify_keys(map) do
    map
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, acc ->
      acc |> stringify_key(key, map[key])
    end)
  end

  defp stringify_key(acc, key, val) when is_map(val) and not is_struct(val) do
    acc
    |> Map.merge(%{to_string(key) => stringify_keys(val)})
  end

  defp stringify_key(acc, key, val) do
    acc
    |> Map.merge(%{to_string(key) => val})
  end
end
