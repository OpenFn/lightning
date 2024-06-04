defmodule Lightning.KafkaTriggers.PipelineWorker do
  alias Lightning.KafkaTriggers

  use Oban.Worker,
    queue: :background

  @impl Oban.Worker
  def perform(_args) do
    supervisor = GenServer.whereis(:kafka_pipeline_supervisor)

    if supervisor do
      %{specs: child_count} = Supervisor.count_children(supervisor)

      if child_count == 0 do
        KafkaTriggers.find_enabled_triggers()
        |> Enum.map(fn trigger ->
          KafkaTriggers.generate_pipeline_child_spec(trigger)
        end)
        |> Enum.each(fn child_spec ->
          Supervisor.start_child(supervisor, child_spec)
        end)
      end
    end

    :ok
  end
end
