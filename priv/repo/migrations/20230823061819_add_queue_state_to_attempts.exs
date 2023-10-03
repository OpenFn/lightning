defmodule Lightning.Repo.Migrations.AddQueueStateToAttempts do
  use Ecto.Migration

  def change do
    execute """
            DO $$
            BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type
                           WHERE typname = 'attempt_state'
                             AND typnamespace = 'public'::regnamespace::oid) THEN
                CREATE TYPE public.attempt_state AS ENUM (
                  'available',
                  'claimed',
                  'started',
                  'success',
                  'failed',
                  'killed',
                  'crashed'
                );
              END IF;
            END$$;
            """,
            """
            DO $$
            BEGIN
            IF EXISTS (SELECT 1 FROM pg_type
                       WHERE typname = 'attempt_state'
                         AND typnamespace = 'public'::regnamespace::oid) THEN
                DROP TYPE public.attempt_state;
              END IF;
            END$$;
            """

    alter table(:attempts) do
      add :state, :"public.attempt_state", default: "available", null: false

      add :claimed_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
    end

    create index(:attempts, [:state])

    import Ecto.Query
    # set all existing attempts to "resolved" so that they aren't processed again
    execute(
      fn ->
        repo().update_all(
          from(a in "attempts", update: [set: [state: "success", finished_at: a.updated_at]]),
          []
        )
      end,
      ""
    )

    alter table(:attempts) do
      remove :updated_at, :naive_datetime_usec,
        null: false,
        default: fragment("now() at time zone 'utc'")
    end

    alter table(:attempt_runs) do
      remove :updated_at, :naive_datetime_usec,
        null: false,
        default: fragment("now() at time zone 'utc'")
    end
  end
end
