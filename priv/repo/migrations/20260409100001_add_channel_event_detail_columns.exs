defmodule Lightning.Repo.Migrations.AddChannelEventDetailColumns do
  use Ecto.Migration

  def change do
    alter table(:channel_events) do
      add :request_query_string, :text
      add :request_body_size, :bigint
      add :response_body_size, :bigint
      add :request_send_us, :integer
      add :response_duration_us, :integer
    end
  end
end
