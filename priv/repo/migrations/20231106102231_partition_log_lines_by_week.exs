defmodule Lightning.Repo.Migrations.PartitionLogLinesByWeek do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE log_lines
    RENAME TO log_lines_monolith
    """)

    execute("""
    ALTER TABLE log_lines_monolith
    RENAME CONSTRAINT log_lines_pkey TO log_lines_monolith_pkey
    """)

    execute("""
    ALTER INDEX log_lines_attempt_id_index
    RENAME TO log_lines_monolith_attempt_id_index
    """)

    execute("""
    ALTER INDEX log_lines_run_id_index
    RENAME TO log_lines_monolith_run_id_index
    """)

    execute("""
    ALTER TABLE log_lines_monolith
    RENAME CONSTRAINT log_lines_attempt_id_fkey TO log_lines_monolith_attempt_id_fkey
    """)

    execute("""
    ALTER TABLE log_lines_monolith
    RENAME CONSTRAINT log_lines_run_id_fkey TO log_lines_monolith_run_id_fkey
    """)

    execute("""
    CREATE TABLE public.log_lines (
    id uuid NOT NULL,
    message text NOT NULL,
    run_id uuid,
    "timestamp" timestamp(0) without time zone NOT NULL,
    attempt_id uuid,
    level character varying(255),
    source character varying(255),
    CONSTRAINT log_lines_pkey PRIMARY KEY (id, timestamp)
    ) PARTITION BY range(timestamp)
    """)

    Lightning.AdminTools.generate_iso_weeks(~D[2023-01-02], ~D[2024-01-29])
    |> Enum.each(fn {year, wnum, from, to} ->
      execute("""
      CREATE TABLE log_lines_#{year}_#{wnum}
        PARTITION OF log_lines
          FOR VALUES FROM ('#{from}') TO ('#{to}')
      """)
    end)

    execute("""
    CREATE TABLE log_lines_default
    PARTITION OF log_lines
    DEFAULT
    """)

    execute("""
    INSERT INTO log_lines
    SELECT *
    FROM log_lines_monolith
    """)

    execute("""
    CREATE INDEX log_lines_attempt_id_index
    ON public.log_lines
    USING btree (attempt_id)
    """)

    execute("""
    CREATE INDEX log_lines_run_id_index
    ON public.log_lines
    USING btree (run_id)
    """)

    execute("""
    ALTER TABLE public.log_lines
    ADD CONSTRAINT log_lines_attempt_id_fkey
    FOREIGN KEY (attempt_id)
    REFERENCES public.attempts(id)
    ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE public.log_lines
    ADD CONSTRAINT log_lines_run_id_fkey
    FOREIGN KEY (run_id)
    REFERENCES public.runs(id)
    ON DELETE CASCADE
    """)
  end

  def down do
    Lightning.AdminTools.generate_iso_weeks(~D[2023-01-02], ~D[2024-01-29])
    |> Enum.each(fn {year, wnum, _from, _to} ->
      execute("""
      ALTER TABLE IF EXISTS log_lines
      DETACH PARTITION log_lines_#{year}_#{wnum}
      """)

      execute("""
      DROP TABLE IF EXISTS log_lines_#{year}_#{wnum}
      """)
    end)

    execute("""
    ALTER TABLE IF EXISTS log_lines DETACH PARTITION log_lines_default
    """)

    execute("""
    DROP TABLE IF EXISTS log_lines_default
    """)

    execute("""
    DROP TABLE IF EXISTS public.log_lines
    """)

    execute("""
    ALTER TABLE IF EXISTS log_lines_monolith
    RENAME TO log_lines
    """)

    execute("""
    ALTER TABLE log_lines
    RENAME CONSTRAINT log_lines_monolith_pkey TO log_lines_pkey
    """)

    execute("""
    ALTER INDEX log_lines_monolith_attempt_id_index
    RENAME TO log_lines_attempt_id_index
    """)

    execute("""
    ALTER INDEX log_lines_monolith_run_id_index
    RENAME TO log_lines_run_id_index
    """)

    execute("""
    ALTER TABLE log_lines
    RENAME CONSTRAINT log_lines_monolith_attempt_id_fkey TO log_lines_attempt_id_fkey
    """)

    execute("""
    ALTER TABLE log_lines
    RENAME CONSTRAINT log_lines_monolith_run_id_fkey TO log_lines_run_id_fkey
    """)
  end
end
