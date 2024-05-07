defmodule Lightning.KafkaTriggers.PipelineWorker do

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.Pipeline

  use Oban.Worker,
    queue: :background

  @impl Oban.Worker
  def perform(_args) do
    supervisor = GenServer.whereis(:kafka_pipeline_supervisor)

    if supervisor do
      %{specs: child_count} = Supervisor.count_children(supervisor)

      if child_count == 0 do
        KafkaTriggers.find_enabled_triggers
        |> Enum.map(fn trigger ->
          %{
            "group_id" => group_id,
            "hosts" => hosts_list,
            "sasl" => sasl_options,
            "ssl" => ssl,
            "topics" => topics,
          } = trigger.kafka_configuration

          hosts = hosts_list |> Enum.map(& List.to_tuple(&1))
          sasl =
            case sasl_options do
              options when is_list(options) ->
                options |> List.to_tuple()
              nil ->
                nil
            end

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
                  sasl: sasl,
                  ssl: ssl,
                  topics: topics
                ]
              ]
            }
          }
        end)
        |> Enum.each(fn child_spec ->
          Supervisor.start_child(supervisor, child_spec)
        end)
      end
    end

    :ok
  end
end
