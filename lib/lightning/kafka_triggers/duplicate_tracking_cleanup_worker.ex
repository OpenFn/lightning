defmodule Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker do
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  alias Lightning.Repo
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord

  @impl Oban.Worker
  def perform(_opts) do
    TriggerKafkaMessageRecord
    |> Repo.delete_all()

    {:error, :bah}
  end
end
