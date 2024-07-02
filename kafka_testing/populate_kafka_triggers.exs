# Create the triggers

alias Lightning.Workflows.Workflow
alias Lightning.Workflows.Trigger
alias Lightning.Repo

workflow = Workflow |> Repo.all() |> hd()

hosts = [["localhost", 9096], ["localhost", 9095], ["localhost", 9094]]

foo_configuration = %{
  group_id: "my-foo-group",
  hosts: hosts,
  partition_timestamps: %{},
  sasl: nil,
  ssl: false,
  topics: ["foo_topic"]
}

foo_changeset =
  Trigger.changeset(
    %Trigger{},
    %{type: :kafka, workflow_id: workflow.id, enabled: true, kafka_configuration: foo_configuration}
  )

foo_changeset |> Repo.insert()

bar_configuration = %{
  group_id: "my-bar-group",
  hosts: hosts,
  partition_timestamps: %{},
  sasl: nil,
  ssl: false,
  topics: ["bar_topic"]
}

bar_changeset =
  Trigger.changeset(
    %Trigger{},
    %{type: :kafka, workflow_id: workflow.id, enabled: true, kafka_configuration: bar_configuration}
  )

bar_changeset |> Repo.insert()

baz_configuration = %{
  group_id: "my-baz-group",
  hosts: hosts,
  partition_timestamps: %{},
  sasl: nil,
  ssl: false,
  topics: ["baz_topic"]
}

baz_changeset =
  Trigger.changeset(
    %Trigger{},
    %{type: :kafka, workflow_id: workflow.id, enabled: true, kafka_configuration: baz_configuration}
  )

baz_changeset |> Repo.insert()

# Start the supervisor and have the Oban job start the triggers

alias Lightning.KafkaTriggers.PipelineSupervisor
alias Lightning.KafkaTriggers.PipelineWorker

{:ok, sup} = PipelineSupervisor.start_link([])

PipelineWorker.perform(%Oban.Job{args: %{}})

# bar = GenServer.whereis(:"d799ae88-587f-4370-886e-aab346ec8ef7")
# DynamicSupervisor.terminate_child(sup, bar)

defmodule KafkaTestingUtils do
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.KafkaTriggers.PipelineWorker
  alias Lightning.Workflows.Trigger
  alias Lightning.Repo

  import Ecto.Query

  def start_supervisor_and_children() do
    {:ok, sup} = PipelineSupervisor.start_link([])

    PipelineWorker.perform(%Oban.Job{args: %{}})
  end

  def switch_to_auth_config do
    query = from t in Trigger, where: t.type == :kafka

    triggers = Repo.all(query)

    triggers
    |> Enum.each(fn %{kafka_configuration: config} = trigger ->
      changes = %{
        "hosts" => [["localhost", 9094]],
        "sasl" => ["plain", "user", "bitnami"],
        "ssl" => false
      }
      new_config = config |> Map.merge(changes)
      changeset = Trigger.changeset(trigger, %{kafka_configuration: new_config})
      changeset |> Repo.update()
    end)
  end

  def switch_to_non_auth_config do
    query = from t in Trigger, where: t.type == :kafka

    triggers = Repo.all(query)

    triggers
    |> Enum.each(fn %{kafka_configuration: config} = trigger ->
      changes = %{
        "hosts" => [["localhost", 9096], ["localhost", 9095], ["localhost", 9094]],
        "sasl" => nil,
        "ssl" => false,
      }
      new_config = config |> Map.merge(changes)
      changeset = Trigger.changeset(trigger, %{kafka_configuration: new_config})
      changeset |> Repo.update()
    end)
  end

  def switch_to_confluent_config(host_and_port, username, password) do
    [host, port] = String.split(host_and_port, ":")

    query = from t in Trigger, where: t.type == :kafka

    triggers = Repo.all(query)

    triggers
    |> Enum.each(fn %{kafka_configuration: config} = trigger ->
      changes = %{
        "hosts" => [[host, String.to_integer(port)]],
        "sasl" => ["plain", username, password],
        "ssl" => true
      }
      new_config = config |> Map.merge(changes)
      changeset = Trigger.changeset(trigger, %{kafka_configuration: new_config})
      changeset |> Repo.update()
    end)
  end

  def add_empty_partition_timestamps_to_config do

    all_kafka_triggers()
    |> Enum.each(fn %{kafka_configuration: config} = trigger ->
      changes = %{
        "partition_timestamps" => %{}
      }
      new_config = config |> Map.merge(changes)
      changeset = Trigger.changeset(trigger, %{kafka_configuration: new_config})
      changeset |> Repo.update()
    end)
  end

  def set_initial_offset_reset_policy(policy) do
    all_kafka_triggers()
    |> Enum.each(fn trigger ->
      trigger
      |> update_kafka_configuration("initial_offset_reset_policy", policy)
    end)
  end

  def change_group_ids(group_id_mappings) do
    group_id_mappings
    |> Enum.each(fn [old_id, new_id] ->
      all_kafka_triggers()
      |> find_trigger_for_group(old_id)
      |> update_kafka_configuration("group_id", new_id)
    end)
  end

  def all_kafka_triggers() do
    query = from t in Trigger, where: t.type == :kafka

    Repo.all(query)
  end

  def link_triggers_to_workflow(workflow_id) do
    all_kafka_triggers()
    |> Enum.each(fn trigger ->
      trigger
      |> Trigger.changeset(%{workflow_id: workflow_id})
      |> Repo.update()
    end)
  end

  defp find_trigger_for_group(triggers, required_group_id) do
    triggers
    |> Enum.find(fn trigger ->
      %Trigger{
        kafka_configuration: %{
          "group_id" => group_id
        }
      } = trigger

      group_id == required_group_id
    end)
  end

  defp update_kafka_configuration(trigger, key, val) do
    %{kafka_configuration: old_config} = trigger

    new_config = old_config |> Map.merge(%{key => val})

    trigger
    |> Trigger.changeset(%{kafka_configuration: new_config})
    |> Repo.update()
  end
end

group_id_mappings = [
  ["my-foo-group-1", "my-foo-group"],
  ["my-bar-group-1", "my-bar-group"],
  ["my-baz-group-1", "my-baz-group"],
]

group_id_mappings = [
  ["my-foo-group", "my-foo-group-1"],
  ["my-bar-group", "my-bar-group-1"],
  ["my-baz-group", "my-baz-group-1"],
]

group_id_mappings = [
  ["my-foo-group-1", "my-foo-group-2"],
  ["my-bar-group-1", "my-bar-group-2"],
  ["my-baz-group-1", "my-baz-group-2"],
]

group_id_mappings = [
  ["my-foo-group-2", "my-foo-group-3"],
  ["my-bar-group-2", "my-bar-group-3"],
  ["my-baz-group-2", "my-baz-group-3"],
]

group_id_mappings = [
  ["my-foo-group-3", "my-foo-group-4"],
  ["my-bar-group-3", "my-bar-group-4"],
  ["my-baz-group-3", "my-baz-group-4"],
]
