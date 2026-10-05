defmodule Lightning.Repo.Migrations.NamespaceTriggerCustomPathsByProject do
  use Ecto.Migration

  @moduledoc """
  A webhook's custom path is unique within its project, since the public URL
  carries the project id. Triggers only know their workflow, so the project is
  denormalised onto the trigger and held there by a composite foreign key: the
  pair must match a real `(workflows.id, workflows.project_id)`, and moving a
  workflow between projects carries its triggers along.

  `project_id` is nullable because it only scopes a custom path. A trigger
  without one is reached by its id and needs no project. `Trigger.changeset/2`
  requires the two together.

  `legacy_bare_path` marks the rows that already answer at `/i/<path>`, from
  before paths were namespaced.
  """

  def up do
    create unique_index(:workflows, [:id, :project_id], name: :workflows_id_project_id_index)

    alter table(:triggers) do
      add :project_id, :binary_id
      add :legacy_bare_path, :boolean, null: false, default: false
    end

    execute("""
    UPDATE triggers t
    SET project_id = w.project_id
    FROM workflows w
    WHERE w.id = t.workflow_id
    """)

    execute("""
    ALTER TABLE triggers
    ADD CONSTRAINT triggers_workflow_id_project_id_fkey
    FOREIGN KEY (workflow_id, project_id)
    REFERENCES workflows (id, project_id)
    ON UPDATE CASCADE ON DELETE CASCADE
    """)

    # Soft-deleted workflows are never purged, so a hidden row would refuse its
    # name to a replacement forever. Disabled rows only: webhook ingest ignores
    # `workflows.deleted_at`, so a hidden workflow with an enabled trigger is
    # still serving, and `down/0` cannot put a cleared value back.
    execute("""
    UPDATE triggers SET custom_path = NULL, legacy_bare_path = false
    WHERE enabled = false
      AND workflow_id IN (
        SELECT id FROM workflows WHERE deleted_at IS NOT NULL
      )
    """)

    # A bare `/i/<path>` was the only way to address a custom path before this,
    # and those URLs are in other people's systems. The set is fixed here and
    # never grows, so nobody can claim a bare URL out from under an existing one.
    execute("""
    UPDATE triggers SET legacy_bare_path = true
    WHERE custom_path IS NOT NULL AND type = 'webhook'
    """)

    # Nothing enforced uniqueness before. Webhooks only: a stale path on a cron
    # or kafka row never served a URL and must not outrank one that does. These
    # duplicates already 500d on the old lookup, so the oldest keeps the name and
    # the rest fall back to their generated URL rather than aborting.
    execute("""
    UPDATE triggers SET custom_path = NULL, legacy_bare_path = false
    WHERE id IN (
      SELECT id FROM (
        SELECT id,
               row_number() OVER (
                 PARTITION BY project_id, custom_path ORDER BY inserted_at, id
               ) AS rn
        FROM triggers
        WHERE custom_path IS NOT NULL AND type = 'webhook'
      ) ranked
      WHERE ranked.rn > 1
    )
    """)

    create unique_index(:triggers, [:project_id, :custom_path],
             where: "custom_path IS NOT NULL AND type = 'webhook'",
             name: :triggers_project_id_custom_path_index
           )

    # A bare path was never unique across projects either. The oldest holder
    # keeps the bare URL; the rest keep their namespaced one.
    execute("""
    UPDATE triggers SET legacy_bare_path = false
    WHERE id IN (
      SELECT id FROM (
        SELECT id,
               row_number() OVER (
                 PARTITION BY custom_path ORDER BY inserted_at, id
               ) AS rn
        FROM triggers
        WHERE legacy_bare_path
      ) ranked
      WHERE ranked.rn > 1
    )
    """)

    create unique_index(:triggers, [:custom_path],
             where: "legacy_bare_path",
             name: :triggers_legacy_bare_path_index
           )
  end

  def down do
    drop_if_exists index(:triggers, [:custom_path], name: :triggers_legacy_bare_path_index)

    drop_if_exists index(:triggers, [:project_id, :custom_path],
                     name: :triggers_project_id_custom_path_index
                   )

    execute("ALTER TABLE triggers DROP CONSTRAINT IF EXISTS triggers_workflow_id_project_id_fkey")

    alter table(:triggers) do
      remove :legacy_bare_path
      remove :project_id
    end

    drop_if_exists index(:workflows, [:id, :project_id], name: :workflows_id_project_id_index)
  end
end
