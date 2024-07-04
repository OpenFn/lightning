defmodule Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker do
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord

  @impl Oban.Worker
  def perform(_opts) do
    retention_period =
      Application.get_env(
        :lightning,
        :kafka_pipelines
      )[:duplicate_tracking_retention_seconds]

    threshold_time = DateTime.utc_now() |> DateTime.add(-retention_period)

    query =
      from(
        t in TriggerKafkaMessageRecord,
        where: t.inserted_at < ^threshold_time
      )

    query
    |> Repo.delete_all()

    :ok
  end
end
