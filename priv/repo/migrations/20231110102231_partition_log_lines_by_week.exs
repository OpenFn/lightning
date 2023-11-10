defmodule Lightning.Repo.Migrations.PartitionLogLinesByWeek do
  use Ecto.Migration

  @num_partitions 100

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
    CREATE TABLE log_lines (
      id uuid NOT NULL,
      message text NOT NULL,
      run_id uuid,
      "timestamp" timestamp(6) without time zone NOT NULL,
      attempt_id uuid,
      level character varying(255),
      source character varying(255)
    ) PARTITION BY HASH(attempt_id)
    """)

    manage_partitions(@num_partitions, &create_partition/2)

    execute("""
    INSERT INTO log_lines
    SELECT *
    FROM log_lines_monolith
    """)

    execute("""
    CREATE INDEX log_lines_id_index
    ON log_lines
    USING hash (id)
    """)

    execute("""
    CREATE INDEX log_lines_attempt_id_index
    ON log_lines
    USING hash (attempt_id)
    """)

    execute("""
    CREATE INDEX log_lines_run_id_index
    ON log_lines
    USING hash (run_id)
    """)

    execute("""
    CREATE INDEX log_lines_timestamp_index
    ON log_lines (timestamp ASC)
    """)

    execute("""
    ALTER TABLE log_lines
    ADD CONSTRAINT log_lines_attempt_id_fkey
    FOREIGN KEY (attempt_id)
    REFERENCES attempts(id)
    ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE log_lines
    ADD CONSTRAINT log_lines_run_id_fkey
    FOREIGN KEY (run_id)
    REFERENCES runs(id)
    ON DELETE CASCADE
    """)
  end

  def down do
    manage_partitions(@num_partitions, &drop_partition/2)

    execute("""
    DROP TABLE IF EXISTS log_lines
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

  defp manage_partitions(num_partitions, manage_function) do
    1..num_partitions
    |> Enum.each(&manage_function.(num_partitions, &1))
  end

  defp create_partition(num_partitions, part_num) do
    execute("""
    CREATE TABLE log_lines_#{part_num}
    PARTITION OF log_lines
    FOR VALUES WITH (MODULUS #{num_partitions}, REMAINDER #{part_num - 1})
    """)
  end

  defp drop_partition(_num_partitions, part_num) do
    execute("""
    ALTER TABLE IF EXISTS log_lines
    DETACH PARTITION log_lines_#{part_num}
    """)

    execute("""
    DROP TABLE IF EXISTS log_lines_#{part_num}
    """)
  end
end
