defmodule Lightning.Repo.Migrations.ConvertChannelEventHeadersToJsonb do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE channel_events
    ALTER COLUMN request_headers TYPE jsonb
    USING CASE
      WHEN request_headers IS NULL THEN NULL
      WHEN request_headers::jsonb IS NOT NULL THEN request_headers::jsonb
      ELSE NULL
    END
    """

    execute """
    ALTER TABLE channel_events
    ALTER COLUMN response_headers TYPE jsonb
    USING CASE
      WHEN response_headers IS NULL THEN NULL
      WHEN response_headers::jsonb IS NOT NULL THEN response_headers::jsonb
      ELSE NULL
    END
    """
  end

  def down do
    execute """
    ALTER TABLE channel_events
    ALTER COLUMN request_headers TYPE text
    USING request_headers::text
    """

    execute """
    ALTER TABLE channel_events
    ALTER COLUMN response_headers TYPE text
    USING response_headers::text
    """
  end
end
