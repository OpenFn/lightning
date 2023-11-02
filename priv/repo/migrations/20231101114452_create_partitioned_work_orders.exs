defmodule Lightning.Repo.Migrations.CreatePartitionedWorkOrders do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE work_orders
    RENAME TO work_orders_monolith
    """)

    execute("""
    ALTER TABLE work_orders_monolith
    RENAME CONSTRAINT work_orders_pkey TO work_orders_monolith_pkey
    """)

    execute("""
    ALTER INDEX work_orders_reason_id_index RENAME TO work_orders_monolith_reason_id_index
    """)

    execute("""
    ALTER INDEX work_orders_state_index RENAME TO work_orders_monolith_state_index
    """)

    execute("""
    ALTER INDEX work_orders_workflow_id_index RENAME TO work_orders_monolith_workflow_id_index
    """)

    execute("""
    ALTER TABLE work_orders_monolith
    RENAME CONSTRAINT work_orders_dataclip_id_fkey TO work_orders_monolith_dataclip_id_fkey
    """)

    execute("""
    ALTER TABLE work_orders_monolith
    RENAME CONSTRAINT work_orders_reason_id_fkey TO work_orders_monolith_reason_id_fkey
    """)

    execute("""
    ALTER TABLE work_orders_monolith
    RENAME CONSTRAINT work_orders_trigger_id_fkey TO work_orders_monolith_trigger_id_fkey
    """)

    execute("""
    ALTER TABLE work_orders_monolith
    RENAME CONSTRAINT work_orders_workflow_id_fkey TO work_orders_monolith_workflow_id_fkey
    """)

    execute("""
    CREATE TABLE work_orders (
    id uuid NOT NULL,
    workflow_id uuid NOT NULL,
    reason_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    trigger_id uuid,
    dataclip_id uuid,
    state character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    last_activity timestamp without time zone,
    CONSTRAINT work_orders_pkey PRIMARY KEY (inserted_at, id)
    ) PARTITION BY RANGE (inserted_at)
    """)

    Lightning.AdminTools.generate_iso_weeks(~D[2023-01-02], ~D[2024-01-29])
    |> Enum.each(fn {year, wnum, from, to} ->
      execute("""
      CREATE TABLE work_orders_#{year}_#{wnum}
        PARTITION OF work_orders
          FOR VALUES FROM ('#{from}') TO ('#{to}')
      """)
    end)

    execute("""
    CREATE TABLE work_orders_default
    PARTITION OF work_orders
    DEFAULT
    """)

    execute("""
    INSERT INTO work_orders
    SELECT *
    FROM work_orders_monolith
    """)

    execute("""
    CREATE INDEX work_orders_id_index
    ON work_orders USING hash (id)
    """)

    execute("""
    CREATE INDEX work_orders_reason_id_index
    ON work_orders USING btree (reason_id)
    """)

    execute("""
    CREATE INDEX work_orders_state_index
    ON work_orders USING btree (state);
    """)

    execute("""
    CREATE INDEX work_orders_workflow_id_index
    ON work_orders USING btree (workflow_id)
    """)

    execute("""
    ALTER TABLE work_orders
    ADD CONSTRAINT work_orders_dataclip_id_fkey
    FOREIGN KEY (dataclip_id)
    REFERENCES dataclips(id)
    ON DELETE SET NULL
    """)

    execute("""
    ALTER TABLE work_orders
    ADD CONSTRAINT work_orders_reason_id_fkey
    FOREIGN KEY (reason_id)
    REFERENCES invocation_reasons(id)
    """)

    execute("""
    ALTER TABLE work_orders
    ADD CONSTRAINT work_orders_trigger_id_fkey
    FOREIGN KEY (trigger_id)
    REFERENCES triggers(id)
    ON DELETE SET NULL;
    """)

    execute("""
    ALTER TABLE work_orders
    ADD CONSTRAINT work_orders_workflow_id_fkey
    FOREIGN KEY (workflow_id)
    REFERENCES workflows(id)
    ON DELETE CASCADE;
    """)
  end

  def down do
    Lightning.AdminTools.generate_iso_weeks(~D[2023-01-02], ~D[2024-01-29])
    |> Enum.each(fn {year, wnum, _from, _to} ->
      execute("""
      ALTER TABLE work_orders DETACH PARTITION work_orders_#{year}_#{wnum}
      """)

      execute("""
      DROP TABLE work_orders_#{year}_#{wnum}
      """)
    end)

    execute("""
    ALTER TABLE work_orders DETACH PARTITION work_orders_default
    """)

    execute("""
    DROP TABLE work_orders_default
    """)

    execute("""
    DROP TABLE IF EXISTS work_orders
    """)

    execute("""
    ALTER TABLE work_orders_monolith
    RENAME TO work_orders
    """)

    execute("""
    ALTER TABLE work_orders
    RENAME CONSTRAINT work_orders_monolith_pkey TO work_orders_pkey
    """)

    execute("""
    ALTER INDEX work_orders_monolith_reason_id_index RENAME TO work_orders_reason_id_index
    """)

    execute("""
    ALTER INDEX work_orders_monolith_state_index RENAME TO work_orders_state_index
    """)

    execute("""
    ALTER INDEX work_orders_monolith_workflow_id_index RENAME TO work_orders_workflow_id_index
    """)

    execute("""
    ALTER TABLE work_orders
    RENAME CONSTRAINT work_orders_monolith_dataclip_id_fkey TO work_orders_dataclip_id_fkey
    """)

    execute("""
    ALTER TABLE work_orders
    RENAME CONSTRAINT work_orders_monolith_reason_id_fkey TO work_orders_reason_id_fkey
    """)

    execute("""
    ALTER TABLE work_orders
    RENAME CONSTRAINT work_orders_monolith_trigger_id_fkey TO work_orders_trigger_id_fkey
    """)

    execute("""
    ALTER TABLE work_orders
    RENAME CONSTRAINT work_orders_monolith_workflow_id_fkey TO work_orders_workflow_id_fkey
    """)
  end
end
