defmodule Lightning.Repo.Migrations.GrantCredentialBodiesToProjectCredentials do
  use Ecto.Migration

  @moduledoc """
  Records which of a credential's bodies a project's share may read.

  Until now a project asserted an environment *name* and resolution matched that
  name against `credential_bodies.name` at run time. The name is typed on a
  different screen from the values, by a different person, with nothing tying
  the two together, so a sandbox admin could type the parent's environment name
  and decrypt the parent's production values.

  This column moves that from a name being matched to a grant being recorded.
  """

  def up do
    # MATCH SIMPLE passes a composite FK when any referencing column is NULL, so
    # a nullable credential_id would let a grant point anywhere. Close that
    # before relying on the constraint.
    null_credential =
      one!("SELECT count(*) FROM project_credentials WHERE credential_id IS NULL")

    if null_credential > 0 do
      raise """
      Refusing to add the grant: found #{null_credential} project_credentials \
      row(s) with a NULL credential_id. These resolve nothing today and the \
      composite foreign key below cannot constrain them, so a grant on such a \
      row would be unchecked. Investigate their provenance, then either delete \
      them (jobs referencing them are nilified by the existing FK) or backfill \
      the credential_id. Do NOT let this migration decide.
      """
    end

    execute "ALTER TABLE project_credentials ALTER COLUMN credential_id SET NOT NULL"

    # The FK target. credential_bodies.id is already the primary key; this pair
    # is what lets the constraint below check the credential as well as the body.
    create unique_index(:credential_bodies, [:id, :credential_id])

    alter table(:project_credentials) do
      add :credential_body_id, :binary_id
    end

    # Composite deliberately: a single-column reference would let a share point
    # at a body belonging to a different credential, which is the same hole in a
    # new place.
    #
    # NO ACTION rather than RESTRICT because the check is deferred to the end of
    # the statement, and deleting a credential relies on two cascades firing
    # inside one statement (project_credentials and credential_bodies both
    # cascade from credential_id). RESTRICT would check too early and make a
    # credential undeletable.
    execute """
            ALTER TABLE project_credentials
              ADD CONSTRAINT project_credentials_credential_body_fkey
              FOREIGN KEY (credential_id, credential_body_id)
              REFERENCES credential_bodies (credential_id, id)
              ON DELETE NO ACTION
            """,
            "ALTER TABLE project_credentials DROP CONSTRAINT project_credentials_credential_body_fkey"

    # Belt and braces on the MATCH SIMPLE hole above, in case credential_id is
    # ever made nullable again.
    create constraint(:project_credentials, :credential_body_needs_credential,
             check: "credential_body_id IS NULL OR credential_id IS NOT NULL"
           )

    # For the FK's delete-time check, and for answering "which shares grant this
    # body" when someone tries to remove an environment.
    create index(:project_credentials, [:credential_body_id])
  end

  def down do
    drop index(:project_credentials, [:credential_body_id])

    drop constraint(:project_credentials, :credential_body_needs_credential)

    execute "ALTER TABLE project_credentials DROP CONSTRAINT project_credentials_credential_body_fkey"

    alter table(:project_credentials) do
      remove :credential_body_id
    end

    drop unique_index(:credential_bodies, [:id, :credential_id])

    execute "ALTER TABLE project_credentials ALTER COLUMN credential_id DROP NOT NULL"
  end

  defp one!(sql) do
    %{rows: [[n]]} = repo().query!(sql)
    n
  end
end
