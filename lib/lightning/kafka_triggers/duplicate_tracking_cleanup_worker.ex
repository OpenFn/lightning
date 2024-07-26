defmodule Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker do
  @moduledoc """
  Repsonsible for cleaing up stale TriggerKafkaMessageRecords entries.
  TriggerKafkaMessageRecords are used to deduplicate incoming messages from
  a Kafka cluster.
  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query

  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Repo

  @impl Oban.Worker
  def perform(_opts) do
    retention_period =
      Lightning.Config.kafka_duplicate_tracking_retention_seconds()

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
