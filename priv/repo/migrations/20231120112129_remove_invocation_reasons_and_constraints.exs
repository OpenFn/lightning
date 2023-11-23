defmodule Lightning.Repo.Migrations.RemoveInvocationReasonsAndConstraints do
  use Ecto.Migration

  def up do
    alter table(:work_orders) do
      remove :reason_id
    end

    alter table(:attempts) do
      remove :reason_id
    end

    drop table(:invocation_reasons)
  end

  def down do
    execute("""
      CREATE TABLE invocation_reasons (
          id uuid NOT NULL,
          type character varying(20) NOT NULL,
          trigger_id uuid,
          user_id uuid,
          run_id uuid,
          dataclip_id uuid,
          inserted_at timestamp(0) without time zone NOT NULL,
          updated_at timestamp(0) without time zone NOT NULL
      );
    """)

    execute("""
      ALTER TABLE invocation_reasons OWNER TO postgres;
    """)

    execute("""
      ALTER TABLE ONLY invocation_reasons
          ADD CONSTRAINT invocation_reasons_pkey PRIMARY KEY (id);
    """)

    execute("""
      CREATE INDEX invocation_reasons_dataclip_id_index ON invocation_reasons USING btree (dataclip_id);
    """)

    execute("""
      CREATE INDEX invocation_reasons_run_id_index ON invocation_reasons USING btree (run_id);
    """)

    execute("""
      CREATE INDEX invocation_reasons_trigger_id_index ON invocation_reasons USING btree (trigger_id);
    """)

    execute("""
      CREATE INDEX invocation_reasons_user_id_index ON invocation_reasons USING btree (user_id);
    """)

    execute("""
      ALTER TABLE ONLY invocation_reasons
          ADD CONSTRAINT invocation_reasons_dataclip_id_fkey FOREIGN KEY (dataclip_id) REFERENCES dataclips(id);
    """)

    execute("""
      ALTER TABLE ONLY invocation_reasons
          ADD CONSTRAINT invocation_reasons_run_id_fkey FOREIGN KEY (run_id) REFERENCES runs(id);
    """)

    execute("""
      ALTER TABLE ONLY invocation_reasons
          ADD CONSTRAINT invocation_reasons_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES triggers(id);
    """)

    execute("""
      ALTER TABLE ONLY invocation_reasons
          ADD CONSTRAINT invocation_reasons_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id);
    """)

    alter table(:work_orders) do
      add :reason_id, references(:invocation_reasons, type: :binary_id), null: false
    end

    alter table(:attempts) do
      add :reason_id, references(:invocation_reasons, type: :binary_id), null: false
    end
  end
end
