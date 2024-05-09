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
  def switch_to_auth_config do
    alias Lightning.Workflows.Trigger
    alias Lightning.Repo

    import Ecto.Query

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
    alias Lightning.Workflows.Trigger
    alias Lightning.Repo

    import Ecto.Query

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
    alias Lightning.Workflows.Trigger
    alias Lightning.Repo

    import Ecto.Query

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
    alias Lightning.Workflows.Trigger
    alias Lightning.Repo

    import Ecto.Query

    query = from t in Trigger, where: t.type == :kafka

    triggers = Repo.all(query)

    triggers
    |> Enum.each(fn %{kafka_configuration: config} = trigger -> 
      changes = %{
        "partition_timestamps" => %{}
      }
      new_config = config |> Map.merge(changes) 
      changeset = Trigger.changeset(trigger, %{kafka_configuration: new_config}) 
      changeset |> Repo.update()
    end)
  end
end
