defmodule Lightning.KafkaTesting.Utils do
  alias Lightning.Jobs
  alias Lightning.KafkaTriggers.PipelineSupervisor
  alias Lightning.KafkaTriggers.PipelineWorker
  alias Lightning.Projects
  alias Lightning.Workflows
  alias Lightning.Workflows.Trigger
  alias Lightning.Repo

  import Ecto.Query

  def start_supervisor_and_children() do
    {:ok, _sup} = PipelineSupervisor.start_link([])

    PipelineWorker.perform(%Oban.Job{args: %{}})
  end

  def create_project_with_kafka_trigger(project_name, owner, trigger_configuration) do
    {:ok, project} =
      Projects.create_project(%{
        name: project_name,
        project_users: [%{user_id: owner.id, role: :owner}]
      })

    {:ok, workflow} =
      Workflows.save_workflow(%{
        name: "#{project_name} Workflow",
        project_id: project.id
      })

    {:ok, trigger} =
      Workflows.build_trigger(%{
        type: :kafka,
        kafka_configuration: trigger_configuration,
        workflow_id: workflow.id
      })

    {:ok, job} =
      Jobs.create_job(%{
        name: "Console log any data recevied",
        body: """
        fn(state => console.log(state); state);
        """,
        adaptor: "@openfn/language-common@latest",
        workflow_id: workflow.id
      })

    {:ok, _edge} =
      Workflows.create_edge(%{
        workflow_id: workflow.id,
        condition_type: :always,
        source_trigger: trigger,
        target_job: job,
        enabled: true
      })
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
