defmodule Lightning.KafkaTriggers.PipelineWorker do

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.Pipeline

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  @impl Oban.Worker
  def perform(_args) do
    supervisor = GenServer.whereis(:kafka_pipeline_supervisor)

    KafkaTriggers.find_enabled_triggers
    |> Enum.map(fn trigger ->
      %{
        "group_id" => group_id,
        "hosts" => hosts_list,
        "topics" => topics,
      } = trigger.kafka_configuration

      hosts = hosts_list |> Enum.map(fn [host, port] -> {host, port} end)

      %{
        id: trigger.id,
        start: {
          Pipeline,
          :start_link,
          [
            [
              group_id: group_id,
              hosts: hosts,
              name: trigger.id |> String.to_atom(),
              topics: topics
            ]
          ]
        }
      }
    end)
    |> Enum.each(fn child_spec ->
      DynamicSupervisor.start_child(supervisor, child_spec)
    end)

    :ok
  end
end
