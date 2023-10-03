defmodule Lightning.Repo.Migrations.AddStateColumnToWorkorders do
  use Ecto.Migration

  def change do
    execute """
            DO $$
            BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type
                           WHERE typname = 'workorder_state'
                             AND typnamespace = 'public'::regnamespace::oid) THEN
                CREATE TYPE public.workorder_state AS ENUM (
                  'pending',
                  'running',
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
                       WHERE typname = 'workorder_state'
                         AND typnamespace = 'public'::regnamespace::oid) THEN
                DROP TYPE public.workorder_state;
              END IF;
            END$$;
            """

    alter table(:work_orders) do
      add :state, :"public.workorder_state", default: "pending", null: false

      add :last_activity, :utc_datetime_usec
    end

    create index(:work_orders, [:state])

    import Ecto.Query

    execute(
      fn ->
        repo().update_all(
          from(a in "work_orders",
            update: [
              set: [state: "success", last_activity: a.updated_at]
            ]
          ),
          []
        )
      end,
      ""
    )
  end
end
