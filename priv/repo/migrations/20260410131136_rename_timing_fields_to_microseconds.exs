defmodule Lightning.Repo.Migrations.RenameTimingFieldsToMicroseconds do
  use Ecto.Migration

  def change do
    rename table(:channel_events), :latency_ms, to: :latency_us
    rename table(:channel_events), :ttfb_ms, to: :ttfb_us

    flush()

    execute(
      "UPDATE channel_events SET latency_us = latency_us * 1000",
      "UPDATE channel_events SET latency_us = latency_us / 1000"
    )

    execute(
      "UPDATE channel_events SET ttfb_us = ttfb_us * 1000",
      "UPDATE channel_events SET ttfb_us = ttfb_us / 1000"
    )

    alter table(:channel_events) do
      add :queue_us, :integer
      add :connect_us, :integer
      add :reused_connection, :boolean
    end
  end
end
