defmodule Lightning.Repo.Migrations.RequireProjectCredentialsProjectId do
  use Ecto.Migration

  def up do
    null_project =
      one!("SELECT count(*) FROM project_credentials WHERE project_id IS NULL")

    if null_project > 0 do
      raise """
      Refusing to add NOT NULL: found #{null_project} project_credentials \
      row(s) with a NULL project_id. These are orphaned join rows that the \
      credential-scoping guard cannot classify (see PR #50 Finding 5). \
      Investigate their provenance before proceeding, then either delete \
      them (jobs referencing them will be nilified by the existing FK) or \
      backfill the correct project_id. Do NOT let this migration decide.
      """
    end

    execute "ALTER TABLE project_credentials ALTER COLUMN project_id SET NOT NULL"
  end

  def down do
    execute "ALTER TABLE project_credentials ALTER COLUMN project_id DROP NOT NULL"
  end

  defp one!(sql) do
    %{rows: [[n]]} = repo().query!(sql)
    n
  end
end
