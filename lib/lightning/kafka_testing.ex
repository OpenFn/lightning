defmodule Lightning.KafkaTesting.Utils do
  def which_children() do
    supervisor = GenServer.whereis(:kafka_pipeline_supervisor)
    Supervisor.which_children(supervisor)
  end
end
