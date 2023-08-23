defmodule Lightning.Repo.Migrations.CreateAttemptsQueue do
  use Ecto.Migration

  def change do
    execute """
            DO $$
            BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type
                           WHERE typname = 'attempt_queue_state'
                             AND typnamespace = 'public'::regnamespace::oid) THEN
                CREATE TYPE public.attempt_queue_state AS ENUM (
                  'available',
                  'claimed',
                  'resolved'
                );
              END IF;
            END$$;
            """,
            """
            DO $$
            BEGIN
            IF EXISTS (SELECT 1 FROM pg_type
                       WHERE typname = 'attempt_queue_state'
                         AND typnamespace = 'public'::regnamespace::oid) THEN
                DROP TYPE public.attempt_queue_state;
              END IF;
            END$$;
            """

    create table(:attempts_queue, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :attempt_id, references(:attempts, type: :binary_id)

      add :state, :"public.attempt_queue_state", default: "available", null: false

      add :claimed_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec

      timestamps type: :utc_datetime_usec, updated_at: false
    end

    create index(:attempts_queue, [:attempt_id])
    create index(:attempts_queue, [:state])
  end
end
